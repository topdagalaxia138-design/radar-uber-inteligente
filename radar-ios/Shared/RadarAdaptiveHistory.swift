import Foundation

// Learns only the distribution of legible offers. This is not a model of
// completed trips, actual profit, demand, or acceptance by the driver.
struct RadarObservedRate: Codable {
    let date: Date
    let netPerHour: Double
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
        samples.append(.init(date: now, netPerHour: rate))
        if samples.count > 500 { samples.removeFirst(samples.count - 500) }
    }

    mutating func prune(now: Date) {
        samples.removeAll { now.timeIntervalSince($0.date) > 7 * 24 * 3600 || $0.date > now }
    }

    func target(base: Double, now: Date) -> Double {
        guard base.isFinite, base > 0 else { return base }
        let rates = samples.filter { $0.date <= now && now.timeIntervalSince($0.date) <= 7 * 24 * 3600 }
            .map(\.netPerHour).filter { $0.isFinite && $0 > 0 }.sorted()
        // Require a sample before adapting. Never lower the configured floor,
        // and never increase it by more than 25% from offer observations alone.
        guard rates.count >= 20 else { return base }
        let percentile = rates[Int(Double(rates.count - 1) * 0.6)]
        return max(base, min(base * 1.25, percentile))
    }
}
