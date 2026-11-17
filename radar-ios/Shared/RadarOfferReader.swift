import Foundation

struct RadarReadOutcome {
    let offer: RadarOffer?
    let attempted: Bool
    let reason: String
    let fullSummary: String?
    let cardSummary: String?
}

enum RadarOfferReader {
    // Only numeric/unit fields and category are exposed in diagnostics, never
    // arbitrary OCR text, addresses, images or passenger data.
    static func summary(_ text: String) -> String {
        let source = text.replacingOccurrences(of: ",", with: ".") as NSString
        let regex = try! NSRegularExpression(pattern: #"R\$\s*(\d+(?:\.\d+)?)"#)
        let values = regex.matches(in: source as String, range: NSRange(location: 0, length: source.length))
            .prefix(5).map { source.substring(with: $0.range(at: 1)) }
        let category = text.localizedCaseInsensitiveContains("Priority") ? "Priority"
            : (text.localizedCaseInsensitiveContains("UberX") ? "UberX" : "não identificada")
        return "Categoria: \(category); valores monetários: " + (values.isEmpty ? "nenhum" : values.joined(separator: " | "))
    }

    static func read(initialText: String, accurateFull: () throws -> String,
                     accurateCard: () throws -> String) throws -> RadarReadOutcome {
        let initial = RadarOfferParser.parse(initialText)
        let complete: Bool
        if case .complete = initial { complete = true } else { complete = false }
        guard complete || RadarOfferParser.mightContainOffer(initialText) else {
            let reason: String
            if case .incomplete(let value) = initial { reason = value } else { reason = "Aguardando cartão de oferta" }
            return RadarReadOutcome(offer: nil, attempted: false, reason: reason, fullSummary: nil, cardSummary: nil)
        }
        // Accurate OCR runs even when the fast pass cannot parse the card.
        let fullText = try accurateFull()
        let full = RadarOfferParser.parse(fullText)
        guard case .complete(let candidate) = full else {
            let reason: String
            if case .incomplete(let value) = full { reason = value } else { reason = "Dados incompletos" }
            return RadarReadOutcome(offer: nil, attempted: true, reason: "Leitura precisa da tela: " + reason,
                                    fullSummary: summary(fullText), cardSummary: nil)
        }
        let cardText = try accurateCard()
        let card = RadarOfferParser.parse(cardText)
        guard case .complete(let confirmed) = card else {
            let reason: String
            if case .incomplete(let value) = card { reason = value } else { reason = "Dados incompletos" }
            return RadarReadOutcome(offer: nil, attempted: true, reason: "Leitura precisa do cartão: " + reason,
                                    fullSummary: summary(fullText), cardSummary: summary(cardText))
        }
        guard candidate.hasSameMeasurements(as: confirmed) else {
            return RadarReadOutcome(offer: nil, attempted: true, reason: "As leituras precisas discordaram nos números; sem recomendação",
                                    fullSummary: summary(fullText), cardSummary: summary(cardText))
        }
        return RadarReadOutcome(offer: confirmed, attempted: true, reason: "Dados confirmados nas duas leituras precisas",
                                fullSummary: summary(fullText), cardSummary: summary(cardText))
    }
}
