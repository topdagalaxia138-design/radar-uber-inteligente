import XCTest
@testable import RadarCore
final class RadarFuelCostTests: XCTestCase {
    func testRealConsumptionChangesCost() {
        XCTAssertEqual(RadarFuelCost.perKilometer(pricePerLiter: 4.2, kilometersPerLiter: 9)!, 0.4666667, accuracy: 0.00001)
        XCTAssertEqual(RadarFuelCost.perKilometer(pricePerLiter: 4.2, kilometersPerLiter: 11)!, 0.381818, accuracy: 0.00001)
    }
    func testMissingAndInvalidParametersNeverProduceCost() {
        for input in [0.0, -1, Double.nan, Double.infinity] {
            XCTAssertNil(RadarFuelCost.perKilometer(pricePerLiter: input, kilometersPerLiter: 9))
            XCTAssertNil(RadarFuelCost.perKilometer(pricePerLiter: 4.2, kilometersPerLiter: input))
        }
    }
}
