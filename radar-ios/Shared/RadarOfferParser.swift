import Foundation

struct RadarOffer: Equatable {
    let fare: Double
    let pickupMinutes: Double?
    let tripMinutes: Double?
    let pickupKilometers: Double?
    let tripKilometers: Double?
    let rawText: String

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
    // Conservative first-pass parser. Real offer layouts must be validated and tuned.
    static func parse(_ text: String) -> RadarParseResult {
        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: ",", with: ".")
        let lines = normalized.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let fare = firstMatch(#"R\$\s*(\d{1,4}(?:\.\d{2})?)"#, in: normalized)
            .flatMap(Double.init), fare > 0 else {
            return .incomplete("Não consegui identificar o valor da oferta.")
        }

        let farePattern = try! NSRegularExpression(pattern: #"R\$\s*(\d{1,4}(?:\.\d{2})?)"#)
        guard farePattern.numberOfMatches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) == 1 else {
            return .incomplete("Mais de um valor na tela; oferta ambígua.")
        }
        let pickupLine = lines.first { line in
            line.localizedCaseInsensitiveContains("buscar")
            || line.localizedCaseInsensitiveContains("embarque")
            || line.localizedCaseInsensitiveContains("até o passageiro")
        }
        let tripLine = lines.first { line in
            line.localizedCaseInsensitiveContains("destino")
            || line.localizedCaseInsensitiveContains("viagem")
            || line.localizedCaseInsensitiveContains("chegada")
        }

        let pickupKm = pickupLine.flatMap { firstMatch(#"(\d+(?:\.\d+)?)\s*km"#, in: $0) }.flatMap(Double.init)
        let tripKm = tripLine.flatMap { firstMatch(#"(\d+(?:\.\d+)?)\s*km"#, in: $0) }.flatMap(Double.init)
        let pickupMin = pickupLine.flatMap { firstMatch(#"(\d+(?:\.\d+)?)\s*min"#, in: $0) }.flatMap(Double.init)
        let tripMin = tripLine.flatMap { firstMatch(#"(\d+(?:\.\d+)?)\s*min"#, in: $0) }.flatMap(Double.init)

        guard let pickupKm, let tripKm, let pickupMin, let tripMin else {
            return .incomplete("Oferta reconhecida, mas faltam distância ou tempo separados. Não vou chutar.")
        }

        return .complete(RadarOffer(
            fare: fare,
            pickupMinutes: pickupMin,
            tripMinutes: tripMin,
            pickupKilometers: pickupKm,
            tripKilometers: tripKm,
            rawText: text
        ))
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression),
              let capture = text[range].range(of: #"(\d+(?:\.\d+)?)"#, options: .regularExpression) else {
            return nil
        }
        return String(text[capture])
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
    case reject(reason: String, estimatedNet: Double, netPerHour: Double)
    case insufficient(reason: String)
}

enum RadarDecisionEngine {
    static func evaluate(_ offer: RadarOffer, settings: RadarDecisionSettings) -> RadarDecision {
        guard let minutes = offer.totalMinutes, minutes > 0,
              let kilometers = offer.totalKilometers, kilometers > 0,
              settings.fuelCostPerKilometer >= 0,
              settings.targetNetPerHour > 0 else {
            return .insufficient(reason: "Dados ou meta líquida por hora ainda não configurados.")
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

        let threshold = offer.fare < settings.preferredMinimumFare
            ? settings.targetNetPerHour * settings.exceptionalMultiplier
            : settings.targetNetPerHour
        if netPerHour >= threshold {
            let special = offer.fare >= max(50, settings.preferredMinimumFare * 2) && settings.idleMinutes >= 10
            let note = special ? "Oportunidade de valor elevado após ociosidade; rentabilidade acima da meta." : offer.fare >= settings.preferredMinimumFare
                ? "Lucro por hora acima da sua meta."
                : "Abaixo de R$ 25, mas com rentabilidade excepcional."
            return .accept(reason: note, estimatedNet: net, netPerHour: netPerHour)
        }

        return .reject(reason: "Lucro por hora abaixo da meta configurada.", estimatedNet: net, netPerHour: netPerHour)
    }
}
