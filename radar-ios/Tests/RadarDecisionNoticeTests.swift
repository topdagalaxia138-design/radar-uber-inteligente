import XCTest
@testable import RadarCore

final class RadarDecisionNoticeTests: XCTestCase {
    let settings = RadarDecisionSettings(fuelCostPerKilometer: 0.28, targetNetPerHour: 40, preferredMinimumFare: 25)
    func offer(_ fare: Double, _ minutes: Double, _ km: Double) -> RadarOffer {
        RadarOffer(fare: fare, pickupMinutes: 0, tripMinutes: minutes,
                   pickupKilometers: 0, tripKilometers: km, rawText: "")
    }
    func testGoodPriorityOfferProducesGreenNoticeWithoutAddingIncludedBonus() {
        let result = RadarDecisionEngine.evaluate(offer(29.78, 22, 14.5), settings: settings)
        let notice = RadarDecisionNotice(result, destination: nil)
        XCTAssertEqual(notice?.accepted, true)
        XCTAssertTrue(notice?.title.contains("🟢") == true)
        XCTAssertTrue(notice?.subtitle.contains("25.72") == true)
    }
    func testHighFareWithTooMuchTimeProducesRedNotice() {
        let result = RadarDecisionEngine.evaluate(offer(87.43, 180, 51.6), settings: settings)
        let notice = RadarDecisionNotice(result, destination: nil)
        XCTAssertEqual(notice?.accepted, false)
        XCTAssertTrue(notice?.title.contains("🔴") == true)
        XCTAssertTrue(notice?.title.contains("NÃO PEGAR") == true)
    }
    func testSmallFareMeetingNormalTargetIsAccepted() {
        let notice = RadarDecisionNotice(RadarDecisionEngine.evaluate(offer(9.40, 12, 3.5), settings: settings), destination: nil)
        XCTAssertEqual(notice?.accepted, true)
    }
    func testSmallExceptionalFareStillPassesAgreedException() {
        let notice = RadarDecisionNotice(RadarDecisionEngine.evaluate(offer(9.40, 6, 3.5), settings: settings), destination: nil)
        XCTAssertEqual(notice?.accepted, true)
    }
    func testFuelLossProducesRedNotice() {
        let notice = RadarDecisionNotice(RadarDecisionEngine.evaluate(offer(10, 30, 50), settings: settings), destination: nil)
        XCTAssertEqual(notice?.accepted, false)
    }
    func testIncompleteReadingNeverCreatesAcceptOrRejectNotice() {
        XCTAssertNil(RadarDecisionNotice(.insufficient(reason: "Leitura incompleta"), destination: nil))
    }
    func testLegacySnapshotDecodesWithoutDecisionFields() throws {
        let data = Data(#"{"phase":"running","frames":1,"readStatus":"ok","offerSummary":"","notificationStatus":"","processingSeconds":0}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(RadarReadingSnapshot.self, from: data).decisionTitle)
    }
}
