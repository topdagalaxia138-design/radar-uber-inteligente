import XCTest
@testable import RadarCore

final class RadarRuntimePolicyTests: XCTestCase {
    func testThermalLoadReducesSamplingAndStopsAtCritical() {
        XCTAssertLessThan(RadarRuntimePolicy.frameInterval(thermalLevel: 0), RadarRuntimePolicy.frameInterval(thermalLevel: 1))
        XCTAssertLessThan(RadarRuntimePolicy.frameInterval(thermalLevel: 1), RadarRuntimePolicy.frameInterval(thermalLevel: 2))
        XCTAssertEqual(RadarRuntimePolicy.frameInterval(thermalLevel: 3), .infinity)
    }
    func testThermalProtectionStopsBeforeCriticalState() {
        XCTAssertFalse(RadarRuntimePolicy.shouldStopForHeat(thermalLevel: 0))
        XCTAssertFalse(RadarRuntimePolicy.shouldStopForHeat(thermalLevel: 1))
        XCTAssertTrue(RadarRuntimePolicy.shouldStopForHeat(thermalLevel: 2))
        XCTAssertTrue(RadarRuntimePolicy.shouldStopForHeat(thermalLevel: 3))
    }
    func testIdleScreenDoesNotRequireContinuousPreciseOCR() {
        XCTAssertFalse(RadarRuntimePolicy.needsAccurateRead(offer: false, payment: false, finance: false, secondsSinceFallback: 1))
        XCTAssertTrue(RadarRuntimePolicy.needsAccurateRead(offer: false, payment: false, finance: false, secondsSinceFallback: 3))
        XCTAssertTrue(RadarRuntimePolicy.needsAccurateRead(offer: true, payment: false, finance: false, secondsSinceFallback: 0))
        XCTAssertTrue(RadarRuntimePolicy.needsAccurateRead(offer: false, payment: true, finance: false, secondsSinceFallback: 0))
        XCTAssertTrue(RadarRuntimePolicy.needsAccurateRead(offer: false, payment: false, finance: true, secondsSinceFallback: 0))
    }
    func testFailureHasOnlyOnePromptRetryAndNoExpiredRetry() {
        XCTAssertTrue(RadarRuntimePolicy.canRetryFailedNotice(age: 2, secondsSinceFailure: 1, alreadyRetried: false))
        XCTAssertFalse(RadarRuntimePolicy.canRetryFailedNotice(age: 2, secondsSinceFailure: 0.1, alreadyRetried: false))
        XCTAssertFalse(RadarRuntimePolicy.canRetryFailedNotice(age: 7, secondsSinceFailure: 2, alreadyRetried: false))
        XCTAssertFalse(RadarRuntimePolicy.canRetryFailedNotice(age: 2, secondsSinceFailure: 1, alreadyRetried: true))
    }
    func testGateCanReleaseFailedDeliveryWithoutRepeatingSuccessfulOnes() {
        var gate = RadarOfferGate()
        let offer = RadarOffer(fare: 20, pickupMinutes: 2, tripMinutes: 8,
                               pickupKilometers: 1, tripKilometers: 4, rawText: "")
        let now = Date()
        XCTAssertTrue(gate.shouldDeliver(offer, now: now))
        XCTAssertFalse(gate.shouldDeliver(offer, now: now))
        gate.allowRetry(offer)
        XCTAssertTrue(gate.shouldDeliver(offer, now: now))
        XCTAssertFalse(gate.shouldDeliver(offer, now: now))
    }
    func testDiagnosticHistoryIsBoundedAndLegacySnapshotStillDecodes() throws {
        var snapshot = try JSONDecoder().decode(RadarReadingSnapshot.self,
            from: Data(#"{"phase":"running","frames":1,"readStatus":"ok","offerSummary":"","notificationStatus":"","processingSeconds":0}"#.utf8))
        XCTAssertNil(snapshot.runtime)
        for index in 0..<50 { snapshot.runtimeEvent("test", String(index)) }
        XCTAssertEqual(snapshot.runtime?.events.count, 24)
        let restored = try JSONDecoder().decode(RadarReadingSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.runtime?.events.last?.message, "49")
    }
    func testReportedUberXCardIsReadableAndFuelChangesDecision() {
        let text = """
        UberX
        Exclusivo
        R$ 17,59
        Est. de R$1,12/km
        8 min • 7.6 km
        Endereço de teste
        4,88 (579)
        Verificado
        8 minutos • 8.1 km
        Outro endereço
        Aceitar
        """
        guard case .complete(let offer) = RadarOfferParser.parse(text) else { return XCTFail() }
        XCTAssertEqual(offer.totalMinutes, 16)
        XCTAssertEqual(offer.totalKilometers!, 15.7, accuracy: 0.001)
        let highFuel = RadarDecisionSettings(fuelCostPerKilometer: 4.2 / 9, targetNetPerHour: 40, preferredMinimumFare: 25)
        let lowerFuel = RadarDecisionSettings(fuelCostPerKilometer: 0.372, targetNetPerHour: 40, preferredMinimumFare: 25)
        guard case .reject = RadarDecisionEngine.evaluate(offer, settings: highFuel) else { return XCTFail() }
        guard case .accept = RadarDecisionEngine.evaluate(offer, settings: lowerFuel) else { return XCTFail() }
    }
}
