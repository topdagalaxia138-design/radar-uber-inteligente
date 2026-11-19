import XCTest
@testable import RadarCore

final class RadarShortTripTests: XCTestCase {
    let settings = RadarDecisionSettings(fuelCostPerKilometer: 0.28, targetNetPerHour: 40, preferredMinimumFare: 25)
    func offer(_ fare: Double, minutes: Double, km: Double) -> RadarOffer {
        RadarOffer(fare: fare, pickupMinutes: 2, tripMinutes: minutes - 2,
                   pickupKilometers: 1, tripKilometers: km - 1, rawText: "")
    }
    func testEightReaisSevenMinutesApprovesAfterFuel() {
        let decision = RadarDecisionEngine.evaluate(offer(8, minutes: 7, km: 3), settings: settings)
        guard case .accept(_, let net, let hourly) = decision else { return XCTFail() }
        XCTAssertEqual(net, 7.16, accuracy: 0.001)
        XCTAssertEqual(hourly / 60, 1.022857, accuracy: 0.001)
        XCTAssertTrue(RadarDecisionNotice(decision, destination: nil)!.subtitle.contains("1.02/min"))
    }
    func testSevenReaisCanPassWithoutExceptionalMultiplier() {
        guard case .accept = RadarDecisionEngine.evaluate(offer(7, minutes: 8, km: 4), settings: settings) else { return XCTFail() }
    }
    func testLongPickupStillRejectsSmallFare() {
        guard case .reject = RadarDecisionEngine.evaluate(offer(8, minutes: 20, km: 8), settings: settings) else { return XCTFail() }
    }
    func testGrossOneRealPerMinuteDoesNotHideFuelCost() {
        guard case .reject = RadarDecisionEngine.evaluate(offer(8, minutes: 8, km: 12), settings: settings) else { return XCTFail() }
    }
    func testCrossingTwentyFiveDoesNotChangeThreshold() {
        for fare in [24.99, 25.0] {
            guard case .accept = RadarDecisionEngine.evaluate(offer(fare, minutes: 30, km: 10), settings: settings) else { return XCTFail() }
        }
    }
}
