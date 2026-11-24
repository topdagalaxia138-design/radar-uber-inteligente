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
        var caution = false
        switch decision {
        case .accept(let message, let amount, let rate):
            accepted = true; reason = message; net = amount; hourly = rate
        case .caution(let message, let amount, let rate):
            accepted = false; caution = true; reason = message; net = amount; hourly = rate
        case .reject(let message, let amount, let rate):
            accepted = false; reason = message; net = amount; hourly = rate
        case .insufficient:
            return nil
        }
        title = caution ? "🟡 RADAR • ATENÇÃO" : accepted ? "🟢 RADAR • PEGAR" : "🔴 RADAR • NÃO PEGAR"
        subtitle = String(format: "Após combustível R$ %.2f • R$ %.2f/min", net, hourly / 60)
        body = reason + (destination.map { "\nDestino: " + $0 } ?? "")
    }
}

