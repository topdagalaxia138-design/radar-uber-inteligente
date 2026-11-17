import XCTest
@testable import RadarCore

final class RadarCarPlayAvailabilityTests: XCTestCase {
    func testUnsupportedInstallationExplainsAppleRequirement() {
        XCTAssertTrue(RadarCarPlayAvailability.unsupported.message.contains("indisponível"))
        XCTAssertTrue(RadarCarPlayAvailability.unsupported.message.contains("Apple"))
    }
    func testEnabledPermissionDoesNotClaimPhysicalDisplayVerified() {
        XCTAssertTrue(RadarCarPlayAvailability.enabled.message.contains("ainda precisa ser testada"))
    }
    func testDisabledPermissionPointsToSettings() {
        XCTAssertTrue(RadarCarPlayAvailability.disabled.message.contains("ajustes"))
    }
}
