import XCTest
@testable import RadarCore

final class RadarCoreTests: XCTestCase {
    func offer(_ fare: Double = 43) -> RadarOffer {
        RadarOffer(fare: fare, pickupMinutes: 10, tripMinutes: 20,
                   pickupKilometers: 2, tripKilometers: 10, rawText: "")
    }
    func testOnlyExceptionalSmallFaresPass() {
        let settings = RadarDecisionSettings(fuelCostPerKilometer: 0.28, targetNetPerHour: 40, preferredMinimumFare: 25)
        if case .accept = RadarDecisionEngine.evaluate(offer(), settings: settings) {} else { XCTFail() }
        if case .reject = RadarDecisionEngine.evaluate(offer(24), settings: settings) {} else { XCTFail() }
    }
    func testMissingTargetNeverApproves() {
        let settings = RadarDecisionSettings(fuelCostPerKilometer: 0.28, targetNetPerHour: 0, preferredMinimumFare: 25)
        if case .insufficient = RadarDecisionEngine.evaluate(offer(), settings: settings) {} else { XCTFail() }
    }
    func testInvalidNumbersNeverApprove() {
        let settings = RadarDecisionSettings(fuelCostPerKilometer: .nan, targetNetPerHour: 40, preferredMinimumFare: 25)
        if case .insufficient = RadarDecisionEngine.evaluate(offer(), settings: settings) {} else { XCTFail() }
    }
    func testRepositionCanMakeOfferUnprofitable() {
        var settings = RadarDecisionSettings(fuelCostPerKilometer: 0.28, targetNetPerHour: 40, preferredMinimumFare: 25)
        settings.repositionKilometers = 20
        settings.repositionMinutes = 40
        if case .reject = RadarDecisionEngine.evaluate(offer(), settings: settings) {} else { XCTFail() }
    }
    func testIncompleteAndAmbiguousScreensStaySilent() {
        for text in ["R$ 43,00", "Saldo R$ 835,00", "R$ 25,00 buscar 2 min 1 km", "R$ 43,00 R$ 10,00\nbuscar 10 min 2 km\nviagem 20 min 10 km"] {
            if case .incomplete = RadarOfferParser.parse(text) {} else { XCTFail(text) }
        }
    }
    func testPortugueseOfferAndNonbreakingSpace() {
        let text = "R$\u{00A0}43,00\nbuscar 10 min 2,0 km\nviagem 20 min 10,0 km"
        guard case .complete(let parsed) = RadarOfferParser.parse(text) else { return XCTFail() }
        XCTAssertEqual(parsed.fare, 43)
        XCTAssertEqual(parsed.totalMinutes, 30)
        XCTAssertEqual(parsed.totalKilometers, 12)
    }
    func testChangingScreenTextDoesNotRepeatAlert() {
        var gate = RadarOfferGate()
        let date = Date()
        XCTAssertTrue(gate.shouldDeliver(offer(), now: date))
        XCTAssertFalse(gate.shouldDeliver(offer(), now: date.addingTimeInterval(1)))
        XCTAssertTrue(gate.shouldDeliver(offer(), now: date.addingTimeInterval(46)))
    }
    func testRentalIsChargedOnceAndCashDoesNotCreditRental() {
        var ledger = RadarWeeklyLedger()
        let cash = RadarCompletedTrip(id: "1", date: Date(), received: 100, fuel: 10, method: .cash)
        XCTAssertTrue(ledger.record(cash))
        XCTAssertFalse(ledger.record(cash))
        XCTAssertEqual(ledger.rentalRemaining, 835)
        XCTAssertTrue(ledger.record(.init(id: "2", date: Date(), received: 900, fuel: 90, method: .uberPix)))
        XCTAssertEqual(ledger.rentalRemaining, 0)
        XCTAssertEqual(ledger.net, 65)
        XCTAssertEqual(ledger.tripsToMinimumBenefit, 78)
    }
}

final class RadarAdaptiveHistoryTests: XCTestCase {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    func sample(_ fare: Double) -> RadarOffer {
        RadarOffer(fare: fare, pickupMinutes: 5, tripMinutes: 25,
                   pickupKilometers: 2, tripKilometers: 8, rawText: "")
    }
    func testColdStartKeepsConfiguredFloor() {
        var history = RadarAdaptiveHistory()
        for _ in 0..<19 { history.observe(sample(100), fuelPerKm: 0.28, now: date) }
        XCTAssertEqual(history.target(base: 40, now: date), 40)
    }
    func testGoodOfferHistoryRaisesThresholdWithinBound() {
        var history = RadarAdaptiveHistory()
        for _ in 0..<20 { history.observe(sample(100), fuelPerKm: 0.28, now: date) }
        XCTAssertEqual(history.target(base: 40, now: date), 50)
    }
    func testPoorOffersNeverLowerFloor() {
        var history = RadarAdaptiveHistory()
        for _ in 0..<25 { history.observe(sample(10), fuelPerKm: 0.28, now: date) }
        XCTAssertEqual(history.target(base: 40, now: date), 40)
    }
    func testExpiredHistoryCannotChangeThreshold() {
        var history = RadarAdaptiveHistory()
        for _ in 0..<20 { history.observe(sample(100), fuelPerKm: 0.28, now: date) }
        XCTAssertEqual(history.target(base: 40, now: date.addingTimeInterval(8 * 86400)), 40)
    }
    func testPersistenceAndBoundedHistory() throws {
        var history = RadarAdaptiveHistory()
        for _ in 0..<510 { history.observe(sample(100), fuelPerKm: 0.28, now: date) }
        let saved = try JSONEncoder().encode(history)
        let restored = try JSONDecoder().decode(RadarAdaptiveHistory.self, from: saved)
        XCTAssertEqual(restored.samples.count, 500)
        XCTAssertEqual(restored.target(base: 40, now: date), 50)
    }
}
