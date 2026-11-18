import ReplayKit
import Vision
import UserNotifications
import CoreVideo

final class SampleHandler: RPBroadcastSampleHandler {
    private var gate = RadarOfferGate()
    private var history = RadarAdaptiveHistory()
    private var lastFrameAt = -Double.infinity

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard RadarEnvironment.sharedContainerAvailable else {
            finishBroadcastWithError(NSError(domain: "Radar", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Sem acesso ao grupo compartilhado; revise a assinatura."
            ]))
            return
        }
        gate = RadarOfferGate()
        lastFrameAt = -Double.infinity
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
        RadarEnvironment.sharedDefaults?.set(false, forKey: "broadcastActive")
        RadarEnvironment.readingStore?.update { $0.phase = "paused" }
    }
    override func broadcastResumed() {
        RadarEnvironment.sharedDefaults?.set(true, forKey: "broadcastActive")
        RadarEnvironment.readingStore?.update { $0.phase = "running" }
    }
    override func broadcastFinished() {
        RadarEnvironment.sharedDefaults?.set(false, forKey: "broadcastActive")
        RadarEnvironment.readingStore?.update { $0.phase = "stopped" }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video,
              ProcessInfo.processInfo.systemUptime - lastFrameAt >= 0.75,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrameAt = ProcessInfo.processInfo.systemUptime
        // Release Vision's temporary buffers at each frame, important in a
        // memory-constrained broadcast extension.
        autoreleasepool { process(pixels) }
    }

    private func text(in pixels: CVPixelBuffer, level: VNRequestTextRecognitionLevel, region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.regionOfInterest = region
        request.recognitionLanguages = ["pt-BR", "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cvPixelBuffer: pixels).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
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
        }
        defer {
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            RadarEnvironment.sharedDefaults?.set(elapsed, forKey: "lastProcessingSeconds")
            RadarEnvironment.readingStore?.update {
                $0.lastProcessedAt = Date()
                $0.processingSeconds = elapsed
            }
        }
        do {
            let initial = try text(in: pixels, level: .fast)
            let outcome = try RadarOfferReader.read(initialText: initial,
                accurateFull: { try text(in: pixels, level: .accurate) },
                accurateCard: { try text(in: pixels, level: .accurate,
                    region: CGRect(x: 0, y: 0, width: 1, height: 0.75)) })
            if outcome.attempted {
                RadarEnvironment.readingStore?.update {
                    $0.attemptAt = Date()
                    $0.attemptStatus = outcome.reason
                    $0.fullReadSummary = outcome.fullSummary
                    $0.cardReadSummary = outcome.cardSummary
                }
            }
            guard let offer = outcome.offer else {
                status(outcome.reason)
                return
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            guard elapsed < 7 else {
                status("Processamento excedeu 7 segundos; alerta descartado", forOfferAttempt: true)
                return
            }
            evaluate(offer)
        } catch {
            status("Falha do OCR; tentando novamente no próximo quadro")
        }
    }

    private func evaluate(_ offer: RadarOffer) {
        let defaults = RadarEnvironment.sharedDefaults
        let configuredFuel = defaults?.double(forKey: "fuelCostPerKm") ?? 0.28
        let fuel = configuredFuel > 0 ? configuredFuel : 0.28
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
        guard gate.shouldDeliver(offer, now: now) else {
            RadarEnvironment.readingStore?.update {
                if $0.decisionRecord?.offerKey == offer.measurementKey {
                    $0.decisionRecord?.lastSeenAt = now
                }
            }
            return
        }
        history.observe(offer, fuelPerKm: fuel, now: now)
        defaults?.set(try? JSONEncoder().encode(history), forKey: "observedRateHistory")
        defaults?.set(history.samples.count, forKey: "observedOfferCount")
        defaults?.set(adaptiveTarget, forKey: "adaptiveTarget")
        let summary = String(format: "R$ %.2f • %.0f min • %.1f km",
                             offer.fare, offer.totalMinutes ?? 0, offer.totalKilometers ?? 0)
        let record = RadarDecisionRecord(id: UUID().uuidString, offerKey: offer.measurementKey,
            summary: summary, title: notice.title, detail: notice.subtitle,
            accepted: notice.accepted, firstConfirmedAt: now, lastSeenAt: now)
        defaults?.set(summary, forKey: "lastOfferSummary")
        defaults?.set(now.timeIntervalSince1970, forKey: "lastOfferAt")
        RadarEnvironment.readingStore?.update { $0.beginDecision(record) }
        status(notice.accepted ? "Oferta confirmada; aprovada após combustível"
                              : "Oferta confirmada; reprovada após combustível", forOfferAttempt: true)
        deliver(notice, recordID: record.id)
    }

    private func deliver(_ notice: RadarDecisionNotice, recordID: String) {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = RadarNotifications.offerCategory
        content.sound = .default
        content.title = notice.title
        content.subtitle = notice.subtitle
        content.body = notice.body
        content.threadIdentifier = "radar-offers"
        content.userInfo = ["radarDecisionID": recordID]
        let request = UNNotificationRequest(identifier: "radar-latest-offer", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            RadarEnvironment.readingStore?.update {
                $0.markNotice(recordID: recordID, error: error?.localizedDescription, at: Date())
            }
        }
    }
}
