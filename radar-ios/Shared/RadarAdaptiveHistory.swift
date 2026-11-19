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
        // Observed offers do not prove realized profit or demand. Keep the
        // configured target instead of silently rejecting more offers.
        return base
    }
}
