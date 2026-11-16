import Foundation

struct RadarOfferGate {
    private var lastSeen: [String: Date] = [:]
    mutating func shouldDeliver(_ offer: RadarOffer, now: Date) -> Bool {
        lastSeen = lastSeen.filter { now.timeIntervalSince($0.value) < 45 }
        let key = "\(offer.fare)|\(offer.pickupMinutes ?? -1)|\(offer.tripMinutes ?? -1)|\(offer.pickupKilometers ?? -1)|\(offer.tripKilometers ?? -1)"
        guard lastSeen[key] == nil else { return false }
        lastSeen[key] = now
        return true
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
    private(set) var trips: [RadarCompletedTrip] = []
    // Import only confirmed trips; detected offers never count as earnings.
    mutating func record(_ trip: RadarCompletedTrip) -> Bool {
        guard !trips.contains(where: { $0.id == trip.id }),
              trip.received.isFinite, trip.received >= 0,
              trip.fuel.isFinite, trip.fuel >= 0 else { return false }
        trips.append(trip)
        return true
    }
    var received: Double { trips.reduce(0) { $0 + $1.received } }
    var rentalCredits: Double { trips.filter { $0.method.reducesRental }.reduce(0) { $0 + $1.received } }
    var rentalRemaining: Double { max(0, rental - rentalCredits) }
    var net: Double { received - trips.reduce(0) { $0 + $1.fuel } - rental }
    var tripsToMinimumBenefit: Int { max(0, 80 - trips.count) }
}
