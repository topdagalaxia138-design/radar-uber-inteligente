import Foundation

struct RadarRealizedStrategy {
    struct CityResult {
        let city: String
        let count: Int
        let confirmedEarnings: Double
        let estimatedFuel: Double
        let observedMinutes: Double
        var estimatedNetPerHour: Double { (confirmedEarnings - estimatedFuel) * 60 / observedMinutes }
    }

    static func cityResults(receipts: [RadarReceipt], fuelPerKm: Double, now: Date) -> [CityResult] {
        guard fuelPerKm.isFinite, fuelPerKm >= 0 else { return [] }
        var seen = Set<String>()
        var groups: [String: [(Double, Double, Double)]] = [:]
        for receipt in receipts {
            guard let end = receipt.completedAt, let start = receipt.acceptedAt,
                  end <= now, now.timeIntervalSince(end) <= 28 * 86400,
                  receipt.cancelledAt == nil, let offer = receipt.offer, let city = offer.destinationCity,
                  let earnings = receipt.driverEarnings, earnings.isFinite, earnings >= 0,
                  offer.kilometers.isFinite, offer.kilometers >= 0,
                  end > start, seen.insert(receipt.id).inserted else { continue }
            groups[city, default: []].append((earnings, offer.kilometers * fuelPerKm, end.timeIntervalSince(start) / 60))
        }
        return groups.map { city, rows in
            CityResult(city: city, count: rows.count, confirmedEarnings: rows.reduce(0) { $0 + $1.0 },
                       estimatedFuel: rows.reduce(0) { $0 + $1.1 }, observedMinutes: rows.reduce(0) { $0 + $1.2 })
        }.sorted { $0.estimatedNetPerHour > $1.estimatedNetPerHour }
    }

    // A scenario, not a learned probability: maximum empty minutes affordable
    // at a specified empty distance while maintaining the driver's target.
    static func affordableEmptyMinutes(fare: Double, tripMinutes: Double, tripKm: Double,
                                       emptyKm: Double, fuelPerKm: Double, targetPerHour: Double) -> Double? {
        guard [fare, tripMinutes, tripKm, emptyKm, fuelPerKm, targetPerHour].allSatisfy({ $0.isFinite && $0 >= 0 }),
              tripMinutes > 0, targetPerHour > 0 else { return nil }
        return (fare - (tripKm + emptyKm) * fuelPerKm) * 60 / targetPerHour - tripMinutes
    }
}
