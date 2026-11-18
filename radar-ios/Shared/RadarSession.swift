import Foundation

struct RadarOfferGate {
    private var lastSeen: [String: Date] = [:]
    mutating func shouldDeliver(_ offer: RadarOffer, now: Date) -> Bool {
        lastSeen = lastSeen.filter { now.timeIntervalSince($0.value) < 45 }
        let key = offer.identityKey
        let firstAppearance = lastSeen[key] == nil
        // Keep a continuously visible card suppressed, even after 45 seconds.
        lastSeen[key] = now
        return firstAppearance
    }
}

enum RadarPaymentMethod: String, Codable {
    case uberCard, uberPix, cash, ownTerminal
    var reducesRental: Bool { self == .uberCard || self == .uberPix }
}

struct RadarCompletedTrip: Codable, Identifiable {
    let id: String
    let date: Date
    let received: Double
    let fuel: Double
    let method: RadarPaymentMethod
}

struct RadarWeeklyLedger: Codable {
    var rental: Double = 835
    // Nil follows the current operating week; an explicit date allows review
    // of an earlier week without deleting or moving historical trips.
    var referenceDate: Date? = nil

    var weekInterval: DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        calendar.firstWeekday = 2
        let date = referenceDate ?? Date()
        let shifted = calendar.date(byAdding: .hour, value: -4, to: date)!
        let monday = calendar.dateInterval(of: .weekOfYear, for: shifted)!.start
        let start = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: monday)!
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        return DateInterval(start: start, end: end)
    }
    var weeklyTrips: [RadarCompletedTrip] {
        let interval = weekInterval
        return trips.filter { $0.date >= interval.start && $0.date < interval.end }
    }
    private(set) var trips: [RadarCompletedTrip] = []
    // Import only confirmed trips; detected offers never count as earnings.
    mutating func record(_ trip: RadarCompletedTrip) -> Bool {
        guard !trips.contains(where: { $0.id == trip.id }),
              !trip.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              trip.date.timeIntervalSince1970.isFinite,
              trip.received.isFinite, trip.received >= 0,
              trip.fuel.isFinite, trip.fuel >= 0 else { return false }
        trips.append(trip)
        return true
    }
    var received: Double { weeklyTrips.reduce(0) { $0 + $1.received } }
    var rentalCredits: Double { weeklyTrips.filter { $0.method.reducesRental }.reduce(0) { $0 + $1.received } }
    var rentalRemaining: Double { max(0, rental - rentalCredits) }
    var net: Double { received - weeklyTrips.reduce(0) { $0 + $1.fuel } - rental }
    var tripsToMinimumBenefit: Int { max(0, 80 - weeklyTrips.count) }
}


extension RadarOffer {
    var identityKey: String {
        "\(fare)|\(pickupMinutes ?? -1)|\(tripMinutes ?? -1)|\(pickupKilometers ?? -1)|\(tripKilometers ?? -1)|\(destination ?? "")"
    }
}

extension RadarOffer {
    // Diagnostic key deliberately excludes addresses and raw OCR.
    var measurementKey: String {
        "\(fare)|\(pickupMinutes ?? -1)|\(tripMinutes ?? -1)|\(pickupKilometers ?? -1)|\(tripKilometers ?? -1)"
    }
}
