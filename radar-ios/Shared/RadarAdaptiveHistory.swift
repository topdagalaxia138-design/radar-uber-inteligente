import Foundation

// Learns only the distribution of legible offers. This is not a model of
// completed trips, actual profit, demand, or acceptance by the driver.
struct RadarObservedRate: Codable {
    let date: Date
    let netPerHour: Double
    var destinationCity: String? = nil
}

struct RadarAdaptiveHistory: Codable {
    private(set) var samples: [RadarObservedRate] = []

    mutating func observe(_ offer: RadarOffer, fuelPerKm: Double, now: Date) {
        prune(now: now)
        guard let km = offer.totalKilometers, let minutes = offer.totalMinutes,
              km.isFinite, km >= 0, minutes.isFinite, minutes > 0,
              fuelPerKm.isFinite, fuelPerKm >= 0, offer.fare.isFinite, offer.fare > 0 else { return }
        let rate = (offer.fare - km * fuelPerKm) * 60 / minutes
        guard rate.isFinite, rate > 0 else { return }
        samples.append(.init(date: now, netPerHour: rate, destinationCity: Self.city(in: offer.destination)))
        if samples.count > 500 { samples.removeFirst(samples.count - 500) }
    }

    mutating func prune(now: Date) {
        samples.removeAll { now.timeIntervalSince($0.date) > 7 * 24 * 3600 || $0.date > now }
    }

    // Destination is not the driver's current city. Keep the distinction explicit.
    static func city(in destination: String?) -> String? {
        guard let destination else { return nil }
        let normalized = destination.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        let cities = ["Criciúma", "Içara", "Forquilhinha", "Araranguá", "Maracajá", "Nova Veneza", "Siderópolis", "Morro da Fumaça", "Balneário Rincão", "Cocal do Sul", "Urussanga"]
        let matches = cities.filter { city in
            let name = city.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            return normalized.range(of: "(?:^|[,;])\\s*" + NSRegularExpression.escapedPattern(for: name) + "\\s*(?:$|[,;]|-\\s*sc)", options: .regularExpression) != nil
        }
        return matches.count == 1 ? matches.first : nil
    }

    struct RegionalWindow {
        let city: String
        let weekday: Int
        let hour: Int
        let count: Int
        let medianEstimatedNetPerHour: Double
    }

    func regionalWindows(now: Date) -> [RegionalWindow] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let eligible = samples.filter { $0.destinationCity != nil && $0.date <= now && now.timeIntervalSince($0.date) <= 7 * 86400 }
        let groups = Dictionary(grouping: eligible) { sample in
            "\(sample.destinationCity!)|\(calendar.component(.weekday, from: sample.date))|\(calendar.component(.hour, from: sample.date))"
        }
        return groups.values.compactMap { group -> RegionalWindow? in
            guard group.count >= 5, let first = group.first, let city = first.destinationCity else { return nil }
            let rates = group.map(\.netPerHour).sorted()
            let median = (rates[(rates.count - 1) / 2] + rates[rates.count / 2]) / 2
            return RegionalWindow(city: city, weekday: calendar.component(.weekday, from: first.date),
                hour: calendar.component(.hour, from: first.date), count: group.count, medianEstimatedNetPerHour: median)
        }.sorted { $0.medianEstimatedNetPerHour > $1.medianEstimatedNetPerHour }
    }

    func target(base: Double, now: Date) -> Double {
        // Observed offers do not prove realized profit or demand. Keep the
        // configured target instead of silently rejecting more offers.
        return base
    }
}
