import ReplayKit
import Vision
import UserNotifications

final class SampleHandler: RPBroadcastSampleHandler {
    private let request = VNRecognizeTextRequest()
    private var gate = RadarOfferGate()
    private var observationGate = RadarOfferGate()
    private var history = RadarAdaptiveHistory()
    private var lastFrameAt = ProcessInfo.processInfo.systemUptime

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        request.recognitionLevel = .fast
        request.recognitionLanguages = ["pt-BR", "en-US"]
        request.usesLanguageCorrection = false
        let defaults = UserDefaults(suiteName: "group.br.com.radaruber.app")
        if let data = defaults?.data(forKey: "observedRateHistory"),
           let saved = try? JSONDecoder().decode(RadarAdaptiveHistory.self, from: data) {
            history = saved
        }
        history.prune(now: Date())
        defaults?.set(true, forKey: "broadcastActive")
    }

    override func broadcastPaused() {
        UserDefaults(suiteName: "group.br.com.radaruber.app")?.set(false, forKey: "broadcastActive")
    }
    override func broadcastResumed() {
        UserDefaults(suiteName: "group.br.com.radaruber.app")?.set(true, forKey: "broadcastActive")
    }
    override func broadcastFinished() {
        UserDefaults(suiteName: "group.br.com.radaruber.app")?.set(false, forKey: "broadcastActive")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video,
              ProcessInfo.processInfo.systemUptime - lastFrameAt >= 0.5,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        lastFrameAt = ProcessInfo.processInfo.systemUptime
        let startedAt = lastFrameAt
        UserDefaults(suiteName: "group.br.com.radaruber.app")?.set(Date().timeIntervalSince1970, forKey: "lastFrameAt")
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        do {
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            guard !lines.isEmpty else { return }
            let recognizedText = lines.joined(separator: "\n")

            switch RadarOfferParser.parse(recognizedText) {
            case .incomplete:
                UserDefaults(suiteName: "group.br.com.radaruber.app")?.set("Aguardando oferta completa e legível", forKey: "lastReadStatus")
                return
            case .complete(let offer):
                let defaults = UserDefaults(suiteName: "group.br.com.radaruber.app")
                let fuelCost = defaults?.double(forKey: "fuelCostPerKm") ?? 0.28
                let target = defaults?.double(forKey: "targetNetPerHour") ?? 0
                let now = Date()
                let adaptiveTarget = history.target(base: target, now: now)
                if observationGate.shouldDeliver(offer, now: now) {
                    history.observe(offer, fuelPerKm: fuelCost > 0 ? fuelCost : 0.28, now: now)
                    defaults?.set(try? JSONEncoder().encode(history), forKey: "observedRateHistory")
                    defaults?.set(history.samples.count, forKey: "observedOfferCount")
                }
                defaults?.set(adaptiveTarget, forKey: "adaptiveTarget")
                defaults?.set("Oferta completa reconhecida", forKey: "lastReadStatus")
                var settings = RadarDecisionSettings(
                    fuelCostPerKilometer: fuelCost > 0 ? fuelCost : 0.28,
                    targetNetPerHour: adaptiveTarget,
                    preferredMinimumFare: 25
                )
                settings.idleMinutes = max(0, defaults?.double(forKey: "confirmedIdleMinutes") ?? 0)
                let decision = RadarDecisionEngine.evaluate(offer, settings: settings)
                let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                defaults?.set(elapsed, forKey: "lastProcessingSeconds")
                defaults?.set(Date().timeIntervalSince1970, forKey: "lastOfferAt")
                guard elapsed < 7 else { return }
                if case .accept = decision, gate.shouldDeliver(offer, now: Date()) {
                    deliver(decision)
                }
            }
        } catch {
            // Never invent data or alert the driver on a failed read.
            UserDefaults(suiteName: "group.br.com.radaruber.app")?.set("Falha de leitura; aguardando novo quadro", forKey: "lastReadStatus")
        }
    }

    private func deliver(_ decision: RadarDecision) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch decision {
        case .accept(let reason, let net, let netHour):
            content.title = "RADAR • PEGAR"
            content.subtitle = String(format: "Após combustível R$ %.2f • R$ %.2f/h", net, netHour)
            content.body = reason
        case .reject, .insufficient:
            // Rejected or incomplete offers stay silent by design.
            return
        }

        let notification = UNNotificationRequest(
            identifier: "radar-offer-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(notification) { error in
            UserDefaults(suiteName: "group.br.com.radaruber.app")?.set(
                error?.localizedDescription ?? "Agendada; entrega depende do iOS",
                forKey: "lastNotificationStatus"
            )
        }
    }
}
