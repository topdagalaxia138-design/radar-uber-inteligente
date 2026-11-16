import ReplayKit
import Vision
import UserNotifications

final class SampleHandler: RPBroadcastSampleHandler {
    private let request = VNRecognizeTextRequest()
    private var gate = RadarOfferGate()
    private var lastFrameAt = ProcessInfo.processInfo.systemUptime

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        request.recognitionLevel = .fast
        request.recognitionLanguages = ["pt-BR", "en-US"]
        request.usesLanguageCorrection = false
    }

    override func broadcastPaused() {}
    override func broadcastResumed() {}
    override func broadcastFinished() {}

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video,
              ProcessInfo.processInfo.systemUptime - lastFrameAt >= 0.5,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        lastFrameAt = ProcessInfo.processInfo.systemUptime
        let startedAt = lastFrameAt
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        do {
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            guard !lines.isEmpty else { return }
            let recognizedText = lines.joined(separator: "\n")

            switch RadarOfferParser.parse(recognizedText) {
            case .incomplete:
                return
            case .complete(let offer):
                let defaults = UserDefaults(suiteName: "group.br.com.radaruber.app")
                let fuelCost = defaults?.double(forKey: "fuelCostPerKm") ?? 0.28
                let target = defaults?.double(forKey: "targetNetPerHour") ?? 0
                var settings = RadarDecisionSettings(
                    fuelCostPerKilometer: fuelCost > 0 ? fuelCost : 0.28,
                    targetNetPerHour: target,
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
            // OCR failure is silent; never invent offer data.
        }
    }

    private func deliver(_ decision: RadarDecision) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch decision {
        case .accept(let reason, let net, let netHour):
            content.title = "RADAR • PEGAR"
            content.subtitle = String(format: "Líquido estimado R$ %.2f • R$ %.2f/h", net, netHour)
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
