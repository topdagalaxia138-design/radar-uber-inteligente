import XCTest
@testable import RadarCore
final class RadarComfortTests: XCTestCase {
    func testComfortCardsUseBothLegs() {
        for product in ["Comfort", "Uber Comfort", "Comfort Exclusivo", "UberX"] {
            let text = "\(product)\nR$ 32,00\n4 min • 2.0 km\n12 minutos • 6.0 km\nDestino sintético\nAceitar"
            XCTAssertTrue(RadarOfferParser.mightContainOffer(text))
            guard case .complete(let offer) = RadarOfferParser.parse(text) else { XCTFail(product); continue }
            XCTAssertEqual(offer.totalMinutes, 16)
            XCTAssertEqual(offer.totalKilometers, 8)
        }
    }
}
