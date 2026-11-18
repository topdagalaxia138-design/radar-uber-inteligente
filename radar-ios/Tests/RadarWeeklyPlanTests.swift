import XCTest
@testable import RadarCore

final class RadarWeeklyPlanTests: XCTestCase {
    func testNoSourceMeansUnknownNotZero() {
        let overview = RadarWeeklyOverview(plan: .init(), ledger: nil)
        XCTAssertNil(overview.confirmedReceived)
        XCTAssertNil(overview.registeredTrips)
        XCTAssertNil(overview.estimatedRentalRemaining)
        XCTAssertNil(overview.cashAndOwnTerminal)
        XCTAssertNil(overview.digitalCredits)
    }
    func testUnknownPassCannotProduceHourlyBudget() {
        let plan = RadarWeeklyPlan()
        XCTAssertTrue(plan.isValid)
        XCTAssertNil(plan.plannedHourlyRequirement)
        XCTAssertEqual(plan.weeklyPersonalGoal!, 1000 * 12.0 / 52, accuracy: 0.001)
    }
    func testKnownBudgetChargesRentOnlyOnceAcrossWeek() {
        let plan = RadarWeeklyPlan(rental: 835, monthlyPersonalGoal: 1300,
                                  workDays: 5, hoursPerDay: 6, passBudget: 65)
        XCTAssertEqual(plan.plannedHours, 30)
        XCTAssertEqual(plan.plannedHourlyRequirement!, (835 + 300 + 65) / 30.0, accuracy: 0.001)
    }
    func testExplicitZeroPassIsDifferentFromUnknown() {
        var plan = RadarWeeklyPlan()
        XCTAssertNil(plan.plannedHourlyRequirement)
        plan.passBudget = 0
        XCTAssertNotNil(plan.plannedHourlyRequirement)
    }
    func testInvalidPlanNeverProducesARequiredRate() {
        for plan in [
            RadarWeeklyPlan(rental: -1, passBudget: 0),
            RadarWeeklyPlan(monthlyPersonalGoal: .infinity, passBudget: 0),
            RadarWeeklyPlan(workDays: 0, passBudget: 0),
            RadarWeeklyPlan(workDays: 8, passBudget: 0),
            RadarWeeklyPlan(hoursPerDay: 7, passBudget: 0),
            RadarWeeklyPlan(hoursPerDay: 0, passBudget: 0),
            RadarWeeklyPlan(passBudget: -.infinity)
        ] {
            XCTAssertFalse(plan.isValid)
            XCTAssertNil(plan.plannedHourlyRequirement)
        }
    }
    func testConfirmedCashIsIncomeWithoutRentalCredit() {
        var ledger = RadarWeeklyLedger()
        XCTAssertTrue(ledger.record(.init(id: "cash", date: Date(), received: 100, fuel: 10, method: .cash)))
        let overview = RadarWeeklyOverview(plan: .init(), ledger: ledger)
        XCTAssertEqual(overview.confirmedReceived, 100)
        XCTAssertEqual(overview.cashAndOwnTerminal, 100)
        XCTAssertEqual(overview.digitalCredits, 0)
        XCTAssertEqual(overview.estimatedRentalRemaining, 835)
        XCTAssertEqual(overview.registeredTrips, 1)
    }
    func testDigitalPaymentsCreditRentalAndOwnTerminalDoesNot() {
        var ledger = RadarWeeklyLedger()
        for (id, method) in [("pix", RadarPaymentMethod.uberPix), ("card", .uberCard), ("terminal", .ownTerminal)] {
            XCTAssertTrue(ledger.record(.init(id: id, date: Date(), received: 100, fuel: 10, method: method)))
        }
        let overview = RadarWeeklyOverview(plan: .init(), ledger: ledger)
        XCTAssertEqual(overview.confirmedReceived, 300)
        XCTAssertEqual(overview.cashAndOwnTerminal, 100)
        XCTAssertEqual(overview.digitalCredits, 200)
        XCTAssertEqual(overview.estimatedRentalRemaining, 635)
        XCTAssertEqual(overview.registeredFuel, 30)
    }
    func testPlanPersistsUnknownPassAsUnknown() throws {
        let plan = try JSONDecoder().decode(RadarWeeklyPlan.self, from: JSONEncoder().encode(RadarWeeklyPlan()))
        XCTAssertNil(plan.passBudget)
        XCTAssertNil(plan.plannedHourlyRequirement)
    }
}

final class RadarDecisionRecordTests: XCTestCase {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    func record(_ id: String) -> RadarDecisionRecord {
        RadarDecisionRecord(id: id, offerKey: id, summary: "R$ 29.78 • 22 min • 14.5 km",
            title: "PEGAR", detail: "Após combustível", accepted: true,
            firstConfirmedAt: date, lastSeenAt: date)
    }
    func testNewOfferClearsPreviousNoticeState() {
        var snapshot = RadarReadingSnapshot()
        snapshot.beginDecision(record("A"))
        snapshot.markNotice(recordID: "A", error: nil, at: date)
        snapshot.beginDecision(record("B"))
        XCTAssertEqual(snapshot.decisionRecord?.noticeState, .awaiting)
        XCTAssertNil(snapshot.decisionRecord?.scheduledAt)
        XCTAssertEqual(snapshot.notificationStatus, "Preparando aviso desta oferta")
    }
    func testLateCallbackCannotAttachToNextOffer() {
        var snapshot = RadarReadingSnapshot()
        snapshot.beginDecision(record("A"))
        snapshot.beginDecision(record("B"))
        snapshot.markNotice(recordID: "A", error: "old error", at: date)
        XCTAssertEqual(snapshot.decisionRecord?.id, "B")
        XCTAssertEqual(snapshot.decisionRecord?.noticeState, .awaiting)
        XCTAssertNil(snapshot.decisionRecord?.noticeMessage)
    }
    func testSchedulingIsNotClaimedAsVisibleDelivery() {
        var snapshot = RadarReadingSnapshot()
        snapshot.beginDecision(record("A"))
        snapshot.markNotice(recordID: "A", error: nil, at: date)
        XCTAssertEqual(snapshot.decisionRecord?.noticeState, .scheduled)
        XCTAssertTrue(snapshot.decisionRecord?.noticeMessage?.contains("não confirmada") == true)
    }
    func testFailedNotificationRemainsAssociatedWithOffer() {
        var snapshot = RadarReadingSnapshot()
        snapshot.beginDecision(record("A"))
        snapshot.markNotice(recordID: "A", error: "Denied", at: date)
        XCTAssertEqual(snapshot.decisionRecord?.noticeState, .failed)
        XCTAssertEqual(snapshot.decisionRecord?.noticeMessage, "Denied")
        XCTAssertNil(snapshot.decisionRecord?.scheduledAt)
    }
    func testRepeatedFramesDoNotRefreshDecisionAge() {
        var r = record("A")
        r.lastSeenAt = date.addingTimeInterval(20)
        XCTAssertFalse(r.isRecent(at: date.addingTimeInterval(20)))
        XCTAssertTrue(r.isRecent(at: date.addingTimeInterval(6)))
        XCTAssertFalse(r.isRecent(at: date.addingTimeInterval(7)))
    }
    func testRecordSurvivesSnapshotPersistence() throws {
        var snapshot = RadarReadingSnapshot()
        snapshot.beginDecision(record("A"))
        let saved = try JSONDecoder().decode(RadarReadingSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(saved.decisionRecord?.id, "A")
        XCTAssertEqual(saved.offerSummary, record("A").summary)
    }
    func testMeasurementKeyDoesNotStoreAddresses() {
        let offer = RadarOffer(fare: 25, pickupMinutes: 5, tripMinutes: 10,
                               pickupKilometers: 1, tripKilometers: 3, rawText: "Private OCR", destination: "Private address")
        XCTAssertFalse(offer.measurementKey.contains("Private"))
    }
    func testContinuousOfferDoesNotBecomeNewEvery45Seconds() {
        var gate = RadarOfferGate()
        let offer = RadarOffer(fare: 25, pickupMinutes: 5, tripMinutes: 10,
                               pickupKilometers: 1, tripKilometers: 3, rawText: "")
        XCTAssertTrue(gate.shouldDeliver(offer, now: date))
        for seconds in stride(from: 10, through: 180, by: 10) {
            XCTAssertFalse(gate.shouldDeliver(offer, now: date.addingTimeInterval(Double(seconds))))
        }
        XCTAssertTrue(gate.shouldDeliver(offer, now: date.addingTimeInterval(226)))
    }
}
