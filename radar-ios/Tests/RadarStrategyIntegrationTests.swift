import XCTest
@testable import RadarCore

final class RadarStrategyIntegrationTests: XCTestCase {
    func testReturnScenarioAndNotice() throws {
        let minutes = try XCTUnwrap(RadarRealizedStrategy.affordableEmptyMinutes(fare: 43, tripMinutes: 30, tripKm: 20, emptyKm: 15, fuelPerKm: 0.307, targetPerHour: 40))
        XCTAssertEqual(minutes, 18.3825, accuracy: 0.001)
        let notice = try XCTUnwrap(RadarDecisionNotice(.accept(reason: "Meta", estimatedNet: 36.86, netPerHour: 73.72), destination: "Forquilhinha", strategy: "Retorno vazio: 18 min"))
        XCTAssertTrue(notice.accepted)
        XCTAssertTrue(notice.body.contains("Retorno vazio: 18 min"))
    }

    func testRegionalHistoryAndReceiptAssociation() throws {
        let now = Date(timeIntervalSince1970: 1795737600)
        let offer = RadarOffer(fare: 43, pickupMinutes: 10, tripMinutes: 20, pickupKilometers: 5, tripKilometers: 15, rawText: "", destination: "Rua A, Forquilhinha - SC")
        var history = RadarAdaptiveHistory()
        for i in 0..<5 { history.observe(offer, fuelPerKm: 0.307, now: now.addingTimeInterval(Double(i))) }
        XCTAssertEqual(history.regionalWindows(now: now.addingTimeInterval(5)).first?.city, "Forquilhinha")
        let snapshot = try XCTUnwrap(RadarTripOfferSnapshot(offer, at: now))
        XCTAssertEqual(snapshot.destinationCity, "Forquilhinha")
        var receipt = RadarReceipt(id: "one", startedAt: now, updatedAt: now)
        receipt.acceptedAt = now
        receipt.completedAt = now.addingTimeInterval(1800)
        receipt.offer = snapshot
        receipt.driverEarnings = 43
        let result = try XCTUnwrap(RadarRealizedStrategy.cityResults(receipts: [receipt, receipt], fuelPerKm: 0.307, now: now.addingTimeInterval(1800)).first)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.estimatedNetPerHour, 73.72, accuracy: 0.001)
    }

    func testPassCrossesMidnightAndExpires() throws {
        let start = Date(timeIntervalSince1970: 1795737600)
        let debit = RadarWalletMovement(occurredAt: start, amount: -42, kind: .passDebit, product: nil)
        var receipt = RadarReceipt(id: "one", startedAt: start, updatedAt: start)
        receipt.completedAt = start.addingTimeInterval(3600)
        receipt.driverEarnings = 28
        let cycle = try XCTUnwrap(RadarPassStrategy.activeCycle(movements: [debit], receipts: [receipt, receipt], now: start.addingTimeInterval(43200)))
        XCTAssertEqual(cycle.remainingToRecover, 14)
        XCTAssertEqual(cycle.expiresAt.timeIntervalSince(start), 86400)
        XCTAssertNil(RadarPassStrategy.activeCycle(movements: [debit], receipts: [receipt], now: start.addingTimeInterval(86400)))
    }

    func testPassPlanCombinesTwoWindows() throws {
        let start = Date(timeIntervalSince1970: 1795737600)
        let windows = [RadarPassStrategy.WorkWindow(start: start, end: start.addingTimeInterval(10800), estimatedNetPerHour: 40),
                       RadarPassStrategy.WorkWindow(start: start.addingTimeInterval(43200), end: start.addingTimeInterval(54000), estimatedNetPerHour: 40)]
        let plan = try XCTUnwrap(RadarPassStrategy.bestActivation(windows: windows, cost: 42, now: start))
        XCTAssertEqual(plan.coveredHours, 6)
        XCTAssertEqual(plan.estimatedNetAfterPass, 198)
    }
}
