import ReplayKit
import Vision
import UserNotifications
import CoreVideo

final class SampleHandler: RPBroadcastSampleHandler {
    private var gate = RadarOfferGate()
    private var history = RadarAdaptiveHistory()
    private var lastFrameAt = -Double.infinity
    private var lastFingerprint: UInt64?
    private var lastFallbackAt = -Double.infinity
    private var lastConfirmedFastText: String?
    private var lastConfirmedReadAt = -Double.infinity
    private var heartbeatAt = -Double.infinity
    private var journeyHeartbeatAt = -Double.infinity
    private var skippedFrames = 0
    private var fastReads = 0
    private var accurateReads = 0
    private var lastThermalLevel: Int?
    private var stoppedForHeat = false
    private var retriedOffers: Set<String> = []
    private let processingLock = NSLock()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard RadarEnvironment.sharedContainerAvailable else {
            finishBroadcastWithError(NSError(domain: "Radar", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Sem acesso ao grupo compartilhado; revise a assinatura."
            ]))
            return
        }
        RadarEnvironment.journeyStore?.update { $0.start(at: Date()) }
        journeyHeartbeatAt = -Double.infinity
        gate = RadarOfferGate()
        lastFrameAt = -Double.infinity
        lastFingerprint = nil
        lastFallbackAt = -Double.infinity
        lastConfirmedFastText = nil
        lastConfirmedReadAt = -Double.infinity
        heartbeatAt = -Double.infinity
        skippedFrames = 0; fastReads = 0; accurateReads = 0
        lastThermalLevel = nil
        stoppedForHeat = false
        retriedOffers = []
        let defaults = RadarEnvironment.sharedDefaults
        if let data = defaults?.data(forKey: "observedRateHistory"),
           let saved = try? JSONDecoder().decode(RadarAdaptiveHistory.self, from: data) {
            history = saved
        }
        history.prune(now: Date())
        RadarEnvironment.readingStore?.update {
            $0 = RadarReadingSnapshot()
            $0.phase = "running"
            $0.startedAt = Date()
            $0.readStatus = "Aguardando imagem da tela"
        }
        defaults?.set(true, forKey: "broadcastActive")
    }
    override func broadcastPaused() {
        RadarEnvironment.journeyStore?.update { $0.finish(at: Date(), interrupted: true) }
        RadarEnvironment.sharedDefaults?.set(false, forKey: "broadcastActive")
        RadarEnvironment.readingStore?.update { $0.phase = "paused" }
    }
    override func broadcastResumed() {
        RadarEnvironment.journeyStore?.update { $0.start(at: Date()) }
        journeyHeartbeatAt = -Double.infinity
        RadarEnvironment.sharedDefaults?.set(true, forKey: "broadcastActive")
        RadarEnvironment.readingStore?.update { $0.phase = "running" }
    }
    override func broadcastFinished() {
        RadarEnvironment.journeyStore?.update { $0.finish(at: Date(), interrupted: stoppedForHeat) }
        RadarEnvironment.sharedDefaults?.set(false, forKey: "broadcastActive")
        RadarEnvironment.readingStore?.update { if !stoppedForHeat { $0.phase = "stopped" } }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, processingLock.try() else { return }
        defer { processingLock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        let thermal = ProcessInfo.processInfo.thermalState
        let level = thermal.rawValue
        let thermalLabel = level == 0 ? "Normal" : level == 1 ? "Elevado — modo econômico"
            : level == 2 ? "Sério — leitura econômica" : "Crítico — leitura interrompida"
        if lastThermalLevel != level {
            lastThermalLevel = level
            RadarEnvironment.readingStore?.update {
                $0.runtimeEvent("thermal_state", "Estado informado pelo iOS: \(level). " + thermalLabel)
            }
        }
        if RadarRuntimePolicy.shouldStopForHeat(thermalLevel: level) {
            guard !stoppedForHeat else { return }
            stoppedForHeat = true
            RadarEnvironment.journeyStore?.update { $0.finish(at: Date(), interrupted: true) }
            RadarEnvironment.readingStore?.update {
                $0.phase = "failed"
                $0.readStatus = "Leitura interrompida por estado térmico crítico; aguarde o iPhone esfriar"
                $0.runtimeEvent("thermal_stop", thermalLabel)
                $0.runtime?.thermal = thermalLabel
            }
            finishBroadcastWithError(NSError(domain: "RadarThermal", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "O iPhone informou estado térmico crítico. Aguarde esfriar antes de reiniciar Radar Leitura."
            ]))
            return
        }
        if now - journeyHeartbeatAt >= 10 {
            journeyHeartbeatAt = now
            RadarEnvironment.journeyStore?.update { $0.heartbeat(at: Date()) }
        }
        guard now - lastFrameAt >= RadarRuntimePolicy.frameInterval(thermalLevel: level),
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let fingerprint = frameFingerprint(pixels)
        if fingerprint != nil && fingerprint == lastFingerprint && now - lastFrameAt < 1.5 {
            skippedFrames += 1
            if now - heartbeatAt >= 1 {
                heartbeatAt = now
                RadarEnvironment.readingStore?.update {
                    $0.lastFrameAt = Date()
                    if $0.runtime == nil { $0.runtime = RadarRuntimeDiagnostics() }
                    $0.runtime?.thermal = thermalLabel
                    $0.runtime?.skippedFrames = skippedFrames
                }
            }
            return
        }
        lastFrameAt = now
        lastFingerprint = fingerprint
        // Rest is measured after OCR finishes, preventing back-to-back expensive reads.
        defer { lastFrameAt = ProcessInfo.processInfo.systemUptime }
        autoreleasepool { process(pixels) }
    }

    // Sample a small grid in memory. No screenshot or fingerprint is persisted.
    private func frameFingerprint(_ pixels: CVPixelBuffer) -> UInt64? {
        guard CVPixelBufferLockBaseAddress(pixels, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let planar = CVPixelBufferIsPlanar(pixels)
        let format = CVPixelBufferGetPixelFormatType(pixels)
        let stride: Int
        let width: Int
        let height: Int
        let bytes: UnsafeMutableRawPointer?
        let channels: Int
        if planar {
            guard format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else { return nil }
            stride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
            width = CVPixelBufferGetWidthOfPlane(pixels, 0)
            height = CVPixelBufferGetHeightOfPlane(pixels, 0)
            bytes = CVPixelBufferGetBaseAddressOfPlane(pixels, 0)
            channels = 1
        } else {
            guard format == kCVPixelFormatType_32BGRA else { return nil }
            stride = CVPixelBufferGetBytesPerRow(pixels)
            width = CVPixelBufferGetWidth(pixels); height = CVPixelBufferGetHeight(pixels)
            bytes = CVPixelBufferGetBaseAddress(pixels)
            channels = 4
        }
        guard width > 0, height > 0, let data = bytes?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var hash: UInt64 = 1469598103934665603
        for row in 0..<32 {
            let y = min(height - 1, height / 5 + row * (height * 4 / 5) / 32)
            for column in 0..<24 {
                let x = min(width - 1, column * width / 24)
                let value = data[y * stride + x * channels + (channels == 4 ? 1 : 0)] >> 4
                hash = (hash ^ UInt64(value)) &* 1099511628211
            }
        }
        return hash
    }

    private func text(in pixels: CVPixelBuffer, level: VNRequestTextRecognitionLevel, region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) throws -> String {
        if level == .fast { fastReads += 1 } else { accurateReads += 1 }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.regionOfInterest = region
        request.recognitionLanguages = ["pt-BR", "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cvPixelBuffer: pixels).perform([request])
        return RadarScreenText.render((request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return RadarTextRegion(text: text, x: Double(box.minX), y: Double(box.minY),
                width: Double(box.width), height: Double(box.height))
        })
    }

    private func status(_ message: String, forOfferAttempt: Bool = false) {
        RadarEnvironment.sharedDefaults?.set(message, forKey: "lastReadStatus")
        RadarEnvironment.readingStore?.update {
            $0.readStatus = message
            if forOfferAttempt { $0.attemptStatus = message }
        }
    }

    private func process(_ pixels: CVPixelBuffer) {
        let started = ProcessInfo.processInfo.systemUptime
        let now = Date()
        RadarEnvironment.readingStore?.update {
            $0.phase = "running"
            $0.lastFrameAt = now
            $0.processingStartedAt = now
            $0.frames += 1
            if $0.runtime == nil { $0.runtime = RadarRuntimeDiagnostics() }
            let level = ProcessInfo.processInfo.thermalState.rawValue
            $0.runtime?.thermal = level == 0 ? "Normal" : level == 1 ? "Elevado — modo econômico" : "Sério — leitura reduzida"
            $0.runtime?.skippedFrames = skippedFrames
        }
        defer {
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            RadarEnvironment.sharedDefaults?.set(elapsed, forKey: "lastProcessingSeconds")
            RadarEnvironment.readingStore?.update {
                $0.lastProcessedAt = Date()
                $0.processingSeconds = elapsed
                $0.runtime?.fastReads = fastReads
                $0.runtime?.accurateReads = accurateReads
            }
        }
        do {
            let fast = try text(in: pixels, level: .fast)
            let readTime = ProcessInfo.processInfo.systemUptime
            if fast == lastConfirmedFastText && readTime - lastConfirmedReadAt < 4 { return }
            // Payment/trip screens can contain a product and a price too.
            // An offer candidate must not crop away lifecycle evidence.
            let hasOffer = RadarOfferParser.mightContainOffer(fast) && RadarPaymentParser.parse(fast) == nil
            let hasPayment = RadarPaymentParser.parse(fast) != nil
            let hasFinance = RadarFinanceParser.mightContainFinancialScreen(fast)
            guard RadarRuntimePolicy.needsAccurateRead(offer: hasOffer, payment: hasPayment, finance: hasFinance,
                secondsSinceFallback: ProcessInfo.processInfo.systemUptime - lastFallbackAt,
                thermalLevel: ProcessInfo.processInfo.thermalState.rawValue) else { return }
            lastFallbackAt = ProcessInfo.processInfo.systemUptime
            // On an offer, leave the top banner outside the first accurate pass.
            // The second cropped pass must still agree on every measurement.
            let initial = try text(in: pixels, level: .accurate,
                region: hasOffer ? CGRect(x: 0, y: 0, width: 1, height: 0.82)
                                 : CGRect(x: 0, y: 0, width: 1, height: 1))
            if let firstPayment = RadarPaymentParser.parse(initial) {
                let verification = fast
                let verifiedPayment = firstPayment == RadarPaymentParser.parse(verification) ? firstPayment : RadarPaymentParser.parse(try text(in: pixels, level: .accurate))
                if firstPayment == verifiedPayment {
                    let saved = RadarEnvironment.paymentStore?.observe(firstPayment, at: now) == true
                    if saved { lastConfirmedFastText = fast; lastConfirmedReadAt = readTime }
                    let paymentStatus = saved ? RadarEnvironment.paymentStore?.load().message
                                              : "Não foi possível salvar a etapa de pagamento"
                    RadarEnvironment.readingStore?.update {
                        $0.financeReadStatus = paymentStatus
                        $0.readStatus = paymentStatus ?? "Pagamento em observação"
                    }
                }
                else {
                    RadarEnvironment.readingStore?.update {
                        $0.financeReadStatus = "Etapa de viagem/pagamento sem confirmação nas duas leituras; registro pendente"
                    }
                }
                return
            }
            if RadarFinanceParser.mightContainFinancialScreen(initial) {
                let firstText = initial
                let secondText = try text(in: pixels, level: .accurate)
                let first = RadarFinanceParser.parse(firstText, now: now)
                let second = RadarFinanceParser.parse(secondText, now: now)
                let message: String
                if let reading = RadarFinanceState.confirmedReading(first, second),
                   ProcessInfo.processInfo.systemUptime - started < 7 {
                    let saved = RadarEnvironment.financeStore?.observe(reading, at: Date()) == true
                    if saved { lastConfirmedFastText = fast; lastConfirmedReadAt = readTime }
                    message = saved ? "Leitura financeira atualizada automaticamente: " + reading.screen
                                    : "Não foi possível salvar a leitura financeira"
                } else {
                    message = "Tela financeira não reconhecida com segurança; nenhum valor importado"
                }
                RadarEnvironment.readingStore?.update {
                    $0.financeReadStatus = message
                    $0.readStatus = message
                }
                return
            }
            let outcome = try RadarOfferReader.read(initialText: initial,
                accurateFull: { initial },
                accurateCard: { try text(in: pixels, level: .accurate,
                    region: CGRect(x: 0, y: 0, width: 1, height: 0.75)) })
            if outcome.attempted {
                RadarEnvironment.readingStore?.update {
                    $0.attemptAt = Date()
                    $0.attemptStatus = outcome.reason
                    $0.fullReadSummary = outcome.fullSummary
                    $0.cardReadSummary = outcome.cardSummary
                    $0.runtimeEvent(outcome.offer == nil ? "read_incomplete" : "offer_confirmed", outcome.reason)
                }
            }
            guard let offer = outcome.offer else {
                status(outcome.reason)
                return
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            guard elapsed < 2.0 else {
                status("Leitura demorou mais de 2 segundos; aviso descartado para evitar atraso", forOfferAttempt: true)
                RadarEnvironment.readingStore?.update { $0.runtimeEvent("late_read", "Aviso não enviado: leitura acima de 2 segundos") }
                return
            }
            RadarEnvironment.paymentStore?.observeOffer(offer, at: now)
            evaluate(offer)
            lastConfirmedFastText = fast; lastConfirmedReadAt = readTime
        } catch {
            status("Falha do OCR; tentando novamente no próximo quadro")
            RadarEnvironment.readingStore?.update { $0.runtimeEvent("ocr_error", (error as NSError).domain + " / " + String((error as NSError).code)) }
        }
    }

    private func evaluate(_ offer: RadarOffer) {
        let defaults = RadarEnvironment.sharedDefaults
        guard let price = defaults?.double(forKey: "fuelPricePerLiter"), price > 0,
              let consumption = defaults?.double(forKey: "fuelKilometersPerLiter"),
              let fuel = RadarFuelCost.perKilometer(pricePerLiter: price, kilometersPerLiter: consumption) else {
            status("Confirme preço por litro e consumo real no Radar antes de recomendar corridas", forOfferAttempt: true)
            return
        }
        let target = defaults?.double(forKey: "targetNetPerHour") ?? 0
        let now = Date()
        let adaptiveTarget = history.target(base: target, now: now)
        var settings = RadarDecisionSettings(fuelCostPerKilometer: fuel,
            targetNetPerHour: adaptiveTarget, preferredMinimumFare: 25)
        settings.idleMinutes = max(0, defaults?.double(forKey: "confirmedIdleMinutes") ?? 0)
        let decision = RadarDecisionEngine.evaluate(offer, settings: settings)
        guard let notice = RadarDecisionNotice(decision, destination: offer.destination) else {
            if case .insufficient(let reason) = decision {
                status("Oferta confirmada, sem recomendação: " + reason, forOfferAttempt: true)
            }
            return
        }
        if let previous = RadarEnvironment.readingStore?.load()?.decisionRecord,
           previous.offerKey == offer.measurementKey, previous.noticeState == .failed,
           RadarRuntimePolicy.canRetryFailedNotice(age: now.timeIntervalSince(previous.firstConfirmedAt),
               secondsSinceFailure: now.timeIntervalSince(previous.lastAttemptAt ?? previous.firstConfirmedAt),
               alreadyRetried: retriedOffers.contains(offer.measurementKey)) {
            retriedOffers.insert(offer.measurementKey)
            gate.allowRetry(offer)
            RadarEnvironment.readingStore?.update { $0.runtimeEvent("retry", "Uma nova tentativa após falha de envio") }
        }
        guard gate.shouldDeliver(offer, now: now) else {
            RadarEnvironment.readingStore?.update {
                if $0.decisionRecord?.offerKey == offer.measurementKey {
                    if $0.decisionRecord?.noticeState != .failed { $0.decisionRecord?.lastSeenAt = now }
                }
            }
            return
        }
        history.observe(offer, fuelPerKm: fuel, now: now)
        defaults?.set(try? JSONEncoder().encode(history), forKey: "observedRateHistory")
        defaults?.set(history.samples.count, forKey: "observedOfferCount")
        defaults?.set(adaptiveTarget, forKey: "adaptiveTarget")
        let offerLabel = String(format: "Oferta R$ %.2f • %.0f min • %.1f km", offer.fare,
                                offer.totalMinutes ?? 0, offer.totalKilometers ?? 0)
        let summary = String(format: "R$ %.2f • %.0f min • %.1f km",
                             offer.fare, offer.totalMinutes ?? 0, offer.totalKilometers ?? 0)
        let record = RadarDecisionRecord(id: UUID().uuidString, offerKey: offer.measurementKey,
            summary: summary, title: notice.title, detail: notice.subtitle,
            accepted: notice.accepted, firstConfirmedAt: now, lastSeenAt: now)
        defaults?.set(summary, forKey: "lastOfferSummary")
        defaults?.set(now.timeIntervalSince1970, forKey: "lastOfferAt")
        RadarEnvironment.readingStore?.update { $0.beginDecision(record); $0.runtimeEvent("decision", notice.title) }
        status(notice.title, forOfferAttempt: true)
        if notice.accepted { deliver(notice, recordID: record.id, offerLabel: offerLabel) }
    }

    private func deliver(_ notice: RadarDecisionNotice, recordID: String, offerLabel: String) {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = RadarNotifications.offerCategory
        content.sound = .default
        content.title = notice.title
        content.subtitle = notice.subtitle
        content.body = offerLabel + "\n" + notice.body
        content.threadIdentifier = "radar-offers"
        content.userInfo = ["radarDecisionID": recordID]
        // A distinct request per decision avoids replacing an earlier banner in place.
        let request = UNNotificationRequest(identifier: "radar-offer-" + recordID, content: content, trigger: nil)
        let submittedAt = Date()
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized, settings.alertSetting == .enabled else {
                RadarEnvironment.readingStore?.update {
                    $0.markNotice(recordID: recordID, error: "Avisos bloqueados ou silenciosos nos ajustes do iPhone", at: Date())
                    $0.runtimeEvent("permission_blocked", "Autorização ou alertas não permitem banner")
                }
                return
            }
            guard Date().timeIntervalSince(submittedAt) < 2.5,
                  RadarEnvironment.readingStore?.load()?.phase == "running" else {
                RadarEnvironment.readingStore?.update {
                    $0.markNotice(recordID: recordID, error: "Envio atrasado ou transmissão encerrada", at: Date())
                    $0.runtimeEvent("late_send", "Aviso descartado após espera ou encerramento")
                }
                return
            }
            center.add(request) { error in
                RadarEnvironment.readingStore?.update {
                    $0.markNotice(recordID: recordID, error: error?.localizedDescription, at: Date())
                    $0.runtimeEvent(error == nil ? "ios_submitted" : "send_failed",
                        error == nil ? "Solicitação aceita pelo iOS; banner não confirmado"
                                     : (error! as NSError).domain + " / " + String((error! as NSError).code))
                }
            }
        }
    }
}



