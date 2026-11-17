import Foundation

// One presentation shared by both approved and rejected offers.
struct RadarDecisionNotice {
    let title: String
    let subtitle: String
    let body: String
    let accepted: Bool

    init?(_ decision: RadarDecision, destination: String?) {
        let reason: String
        let net: Double
        let hourly: Double
        switch decision {
        case .accept(let message, let amount, let rate):
            accepted = true; reason = message; net = amount; hourly = rate
        case .reject(let message, let amount, let rate):
            accepted = false; reason = message; net = amount; hourly = rate
        case .insufficient:
            return nil
        }
        title = accepted ? "🟢 RADAR • PEGAR" : "🔴 RADAR • NÃO PEGAR"
        subtitle = String(format: "Após combustível R$ %.2f • R$ %.2f/h", net, hourly)
        body = reason + (destination.map { "\nDestino: " + $0 } ?? "")
    }
}
