import Foundation

struct RadarOffer: Equatable {
    let fare: Double
    let pickupMinutes: Double?
    let tripMinutes: Double?
    let pickupKilometers: Double?
    let tripKilometers: Double?
    let rawText: String
    var destination: String? = nil

    func hasSameMeasurements(as other: RadarOffer) -> Bool {
        func equal(_ a: Double?, _ b: Double?) -> Bool {
            guard let a, let b, a.isFinite, b.isFinite else { return false }
            return abs(a - b) < 0.001
        }
        return abs(fare - other.fare) < 0.001
            && equal(pickupMinutes, other.pickupMinutes) && equal(tripMinutes, other.tripMinutes)
            && equal(pickupKilometers, other.pickupKilometers) && equal(tripKilometers, other.tripKilometers)
    }

    var totalMinutes: Double? {
        guard let pickupMinutes, let tripMinutes else { return nil }
        return pickupMinutes + tripMinutes
    }

    var totalKilometers: Double? {
        guard let pickupKilometers, let tripKilometers else { return nil }
        return pickupKilometers + tripKilometers
    }
}

enum RadarParseResult {
    case complete(RadarOffer)
    case incomplete(String)
}

enum RadarOfferParser {
    // This gate only chooses whether to attempt accurate OCR. It never approves
    // an offer or supplies missing measurements.
    static func mightContainOffer(_ text: String) -> Bool {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        let lines = normalized.components(separatedBy: .newlines)
        let rows = lines.compactMap(metrics).count
        let action = text.localizedCaseInsensitiveContains("Aceitar")
            || text.localizedCaseInsensitiveContains("Tenho interesse")
        let productLine = lines.contains {
            $0.range(of: #"^\s*(Uber\s*X|(?:Uber\s+)?Comfort|Priority)(?:\s+Exclusivo)?\s*$"#,
                     options: [.regularExpression, .caseInsensitive]) != nil
        }
        return action || ((rows >= 2 || productLine) && text.contains("R$"))
    }

    static func parse(_ text: String) -> RadarParseResult {
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: ",", with: ".")
        let lines = normalized.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        // Ignore unit prices, but never choose arbitrarily between two total fares.
        let money = try! NSRegularExpression(pattern: #"R\$\s*(\d{1,4}(?:\.\d{2})?)(?![\d.])"#)
        let isPriority = lines.contains { $0.localizedCaseInsensitiveContains("Priority") }
        var includedAmounts: [Double] = []
        let source = normalized as NSString
        let fares = money.matches(in: normalized, range: NSRange(location: 0, length: source.length)).compactMap { match -> Double? in
            let tail = source.substring(from: match.range.location + match.range.length)
            if tail.range(of: #"^\s*/\s*(km|min|h)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                return nil
            }
            let value = Double(source.substring(with: match.range(at: 1)))
            let lineRange = source.lineRange(for: match.range)
            let nextLine = source.substring(from: NSMaxRange(lineRange)).components(separatedBy: .newlines).first ?? ""
            let line = (source.substring(with: lineRange) + " " + nextLine)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            let prefix = source.substring(with: NSRange(location: lineRange.location, length: match.range.location - lineRange.location))
            if isPriority, line.contains("inclu"), line.contains("retirada priorit"),
               prefix.range(of: #"[+＋]\s*$"#, options: .regularExpression) != nil,
               let value {
                includedAmounts.append(value)
                return nil
            }
            return value
        }
        guard fares.count == 1, let fare = fares.first, fare.isFinite, fare > 0,
              includedAmounts.count <= 1, includedAmounts.allSatisfy({ $0 >= 0 && $0 <= fare }) else {
            return .incomplete("Valor total ausente ou ambíguo.")
        }

        let pickup = lines.first {
            $0.localizedCaseInsensitiveContains("buscar")
                || $0.localizedCaseInsensitiveContains("embarque")
                || $0.localizedCaseInsensitiveContains("até o passageiro")
        }.flatMap(metrics)
        let trip = lines.first {
            $0.localizedCaseInsensitiveContains("destino")
                || $0.localizedCaseInsensitiveContains("viagem")
                || $0.localizedCaseInsensitiveContains("chegada")
        }.flatMap(metrics)

        if let pickup, let trip {
            return .complete(RadarOffer(fare: fare, pickupMinutes: pickup.minutes,
                tripMinutes: trip.minutes, pickupKilometers: pickup.km, tripKilometers: trip.km, rawText: text))
        }

        // Observed UberX/Priority card: pickup row then trip row, without textual labels.
        // Require the product, offer action and exactly two complete metric rows.
        guard lines.contains(where: { ($0.range(of: #"\b(?:Uber\s*X|(?:Uber\s+)?Comfort)\b"#, options: [.regularExpression, .caseInsensitive]) != nil || $0.localizedCaseInsensitiveContains("Priority")) }),
              lines.contains(where: { $0.localizedCaseInsensitiveContains("Tenho interesse")
                  || $0.localizedCaseInsensitiveContains("Aceitar") }) else {
            return .incomplete("Tela não identificada como cartão de oferta compatível.")
        }
        let rows = lines.enumerated().compactMap { index, line -> (index: Int, minutes: Double, km: Double)? in
            guard let value = metrics(line) else { return nil }
            return (index, value.minutes, value.km)
        }
        guard rows.count == 2, rows[1].minutes > 0, rows[1].km > 0 else {
            return .incomplete("Faltam as duas etapas de tempo e distância; não vou estimar.")
        }
        var offer = RadarOffer(fare: fare, pickupMinutes: rows[0].minutes,
            tripMinutes: rows[1].minutes, pickupKilometers: rows[0].km, tripKilometers: rows[1].km, rawText: text)
        let addressLines = lines.dropFirst(rows[1].index + 1)
            .prefix { !$0.localizedCaseInsensitiveContains("Tenho interesse")
                && !$0.localizedCaseInsensitiveContains("Aceitar") }
            .prefix(2)
        if !addressLines.isEmpty {
            offer.destination = addressLines.joined(separator: ", ")
        }
        return .complete(offer)
    }

    private static func metrics(_ text: String) -> (minutes: Double, km: Double)? {
        let expression = try! NSRegularExpression(
            pattern: #"(\d+(?:\.\d+)?)\s*min(?:utos?)?\s*[•·.\-–—]?\s*\(?\s*(\d+(?:\.\d+)?)\s*km\)?"#,
            options: .caseInsensitive)
        let source = text as NSString
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard matches.count == 1, let match = matches.first,
              let minutes = Double(source.substring(with: match.range(at: 1))),
              let km = Double(source.substring(with: match.range(at: 2))),
              minutes.isFinite, minutes >= 0, km.isFinite, km >= 0 else { return nil }
        return (minutes, km)
    }
}

struct RadarDecisionSettings {
    let fuelCostPerKilometer: Double
    let targetNetPerHour: Double
    let preferredMinimumFare: Double
    var repositionKilometers: Double = 0
    var repositionMinutes: Double = 0
    var idleMinutes: Double = 0
    var exceptionalMultiplier: Double = 1.5
}

enum RadarDecision {
    case accept(reason: String, estimatedNet: Double, netPerHour: Double)
    case caution(reason: String, estimatedNet: Double, netPerHour: Double)
    case reject(reason: String, estimatedNet: Double, netPerHour: Double)
    case insufficient(reason: String)
}

enum RadarDecisionEngine {
    static func evaluate(_ offer: RadarOffer, settings: RadarDecisionSettings) -> RadarDecision {
        guard let minutes = offer.totalMinutes, minutes > 0,
              let kilometers = offer.totalKilometers, kilometers > 0,
              settings.fuelCostPerKilometer >= 0,
              settings.targetNetPerHour > 0 else {
            return .insufficient(reason: "Dados ou meta por hora após combustível ainda não configurados.")
        }

        guard offer.fare.isFinite, minutes.isFinite, kilometers.isFinite,
              settings.fuelCostPerKilometer.isFinite, settings.targetNetPerHour.isFinite,
              settings.repositionKilometers.isFinite, settings.repositionKilometers >= 0,
              settings.repositionMinutes.isFinite, settings.repositionMinutes >= 0,
              settings.idleMinutes.isFinite, settings.idleMinutes >= 0,
              settings.preferredMinimumFare.isFinite, settings.preferredMinimumFare > 0,
              settings.exceptionalMultiplier.isFinite, settings.exceptionalMultiplier >= 1 else {
            return .insufficient(reason: "Parâmetros inválidos.")
        }
        let fuel = (kilometers + settings.repositionKilometers) * settings.fuelCostPerKilometer
        let net = offer.fare - fuel
        let netPerHour = net / ((minutes + settings.repositionMinutes) / 60)

        guard net > 0 else {
            return .reject(reason: "O combustível estimado consome o valor da corrida.", estimatedNet: net, netPerHour: netPerHour)
        }

        // Fare size never raises the profitability requirement: short trips
        // compete on the same fuel-adjusted return per minute as long trips.
        let threshold = settings.targetNetPerHour
        if netPerHour >= threshold {
            let special = offer.fare >= max(50, settings.preferredMinimumFare * 2)
            let note = special ? (settings.idleMinutes >= 10 ? "Oportunidade de valor elevado após ociosidade; rentabilidade acima da meta." : "Oportunidade de valor elevado; rentabilidade acima da meta.") : offer.fare >= settings.preferredMinimumFare
                ? "Valor por hora após combustível acima da meta."
                : "Corrida de valor baixo com retorno por minuto após combustível acima da meta."
            return .accept(reason: note, estimatedNet: net, netPerHour: netPerHour)
        }

        if netPerHour >= threshold * 0.9 {
            return .caution(reason: "Até 10% abaixo da meta após combustível; avalie o destino. Não prevê outra corrida.", estimatedNet: net, netPerHour: netPerHour)
        }
        return .reject(reason: "Valor por hora após combustível abaixo da faixa de atenção.", estimatedNet: net, netPerHour: netPerHour)
    }
}

