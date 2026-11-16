import ReplayKit
import Vision
import UserNotifications
import CoreImage

final class SampleHandler: RPBroadcastSampleHandler {
    private let request = VNRecognizeTextRequest()
    private var lastNotificationKey = ""
    private var lastNotificationAt = Date.distantPast
    private let settings = RadarDecisionSettings(
        fuelCostPerKilometer: 0.28,
        targetNetPerHour: 0, // Must be set from the driver's configured target before recommendations are enabled.
        preferredMinimumFare: 25
    )

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

                let decision = RadarDecisionEngine.evaluate(offer, settings: settings)
                deliver(decision, offer: offer)
            }
        } catch {
            // No offer notification on OCR failure. Never guess.
        }
    }

    private func deliver(_ decision: RadarDecision, offer: RadarOffer) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch decision {
        case .accept(let reason, let net, let netHour):
            content.title = "RADAR • PEGAR"
            content.subtitle = String(format: "Líquido estimado R$ %.2f • R$ %.2f/h", net, netHour)
            content.body = reason
        case .reject(let reason, let net, let netHour):
            // Rejected offers stay silent by design.
            return
        case .insufficient:
            return
        }

        let request = UNNotificationRequest(
            identifier: "radar-offer-\\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
