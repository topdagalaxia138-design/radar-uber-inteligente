import XCTest
@testable import RadarCore

final class RadarUberCardTests: XCTestCase {
    // Transcribed from the user's real UberX layout; street data anonymized.
    let card = """
    UberX
    R$ 87,43
    Est. de R$1,69/km
    18 min • 15.6 km
    Rua de teste, Morro da Fumaça
    5,00 (6)
    34 minutos • 36.0 km
    Avenida de teste, Bairro
    Tubarão
    Tenho interesse
    """

    func testRealLayoutSeparatesFareFromPricePerKm() {
        guard case .complete(let offer) = RadarOfferParser.parse(card) else { return XCTFail() }
        XCTAssertEqual(offer.fare, 87.43)
        XCTAssertEqual(offer.pickupMinutes, 18)
        XCTAssertEqual(offer.tripMinutes, 34)
        XCTAssertEqual(offer.totalMinutes, 52)
        XCTAssertEqual(offer.totalKilometers!, 51.6, accuracy: 0.001)
        XCTAssertTrue(offer.destination?.contains("Tubarão") == true)
        let settings = RadarDecisionSettings(fuelCostPerKilometer: 0.28, targetNetPerHour: 40, preferredMinimumFare: 25)
        guard case .accept(_, let net, let perHour) = RadarDecisionEngine.evaluate(offer, settings: settings) else { return XCTFail() }
        XCTAssertEqual(net, 72.982, accuracy: 0.001)
        XCTAssertEqual(perHour, 84.21, accuracy: 0.01)
    }
    func testCommaMetricsAndParentheses() {
        let changed = card.replacingOccurrences(of: "18 min • 15.6 km", with: "18 min (15,6 km)")
        guard case .complete(let offer) = RadarOfferParser.parse(changed) else { return XCTFail() }
        XCTAssertEqual(offer.pickupKilometers!, 15.6, accuracy: 0.001)
    }
    func testMissingTripNeverRecommends() {
        let changed = card.replacingOccurrences(of: "34 minutos • 36.0 km", with: "")
        if case .incomplete = RadarOfferParser.parse(changed) {} else { XCTFail() }
    }
    func testThirdMetricRowIsAmbiguous() {
        if case .incomplete = RadarOfferParser.parse(card + "\n10 min • 5 km") {} else { XCTFail() }
    }
    func testSecondTotalFareIsAmbiguous() {
        if case .incomplete = RadarOfferParser.parse(card + "\nR$ 20,00") {} else { XCTFail() }
    }
    func testWithoutOfferActionIsNotRecognized() {
        if case .incomplete = RadarOfferParser.parse(card.replacingOccurrences(of: "Tenho interesse", with: "")) {} else { XCTFail() }
    }
    func testWithoutProductIsNotRecognized() {
        if case .incomplete = RadarOfferParser.parse(card.replacingOccurrences(of: "UberX", with: "")) {} else { XCTFail() }
    }
}
