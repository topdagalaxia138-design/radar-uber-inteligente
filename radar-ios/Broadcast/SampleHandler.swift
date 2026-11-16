import ReplayKit
import Vision
import UserNotifications

final class SampleHandler: RPBroadcastSampleHandler {
    private let request = VNRecognizeTextRequest()
    private var lastNotificationKey = ""
    private var lastNotificationAt = Date.distantPast

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
              Date().timeIntervalSince(lastNotificationAt) > 0.35,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

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
                let key = recognizedText
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .lowercased()
                guard key != lastNotificationKey else { return }
                lastNotificationKey = key
                lastNotificationAt = Date()

                let defaults = UserDefaults(suiteName: "group.br.com.radaruber.app")
                let fuelCost = defaults?.double(forKey: "fuelCostPerKm") ?? 0.28
                let target = defaults?.double(forKey: "targetNetPerHour") ?? 0
                let settings = RadarDecisionSettings(
                    fuelCostPerKilometer: fuelCost > 0 ? fuelCost : 0.28,
                    targetNetPerHour: target,
                    preferredMinimumFare: 25
                )
                deliver(RadarDecisionEngine.evaluate(offer, settings: settings))
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
        UNUserNotificationCenter.current().add(notification)
    }
}
