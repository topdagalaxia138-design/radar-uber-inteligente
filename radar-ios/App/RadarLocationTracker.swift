import CoreLocation
import Foundation

// App process is the only writer of GPS totals. Broadcast writes journey timing
// to a different file. Coordinates are retained only for the next distance fix.
final class RadarLocationTracker: NSObject, CLLocationManagerDelegate {
    static let shared = RadarLocationTracker()
    private let manager = CLLocationManager()
    private var thermalObserver: NSObjectProtocol?
    private var previous: CLLocation?
    private var previousJourneyID: String?
    private var armedAt: Date?
    private var lastWrite = Date.distantPast
    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        manager.pausesLocationUpdatesAutomatically = false
        thermalObserver = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
                    self?.stop()
                    self?.status("GPS interrompido por aquecimento; cobertura parcial")
                }
            }
    }
    func start(requestPermission: Bool = false) {
        guard RadarEnvironment.sharedDefaults?.bool(forKey: "journeyGPSEnabled") == true else { return }
        guard ProcessInfo.processInfo.thermalState != .serious && ProcessInfo.processInfo.thermalState != .critical else {
            status("GPS indisponível enquanto o estado térmico estiver sério ou crítico"); return
        }
        if manager.authorizationStatus == .notDetermined {
            if requestPermission { manager.requestWhenInUseAuthorization() }
            return
        }
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            status("GPS sem permissão; combustível do turno indisponível")
            return
        }
        guard armedAt == nil else { return }
        armedAt = Date()
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        status("GPS aguardando a transmissão Radar Leitura")
    }
    func stop() {
        manager.stopUpdatingLocation()
        previous = nil; previousJourneyID = nil; armedAt = nil
        status("GPS da jornada parado")
    }
    private func status(_ text: String) { RadarEnvironment.sharedDefaults?.set(text, forKey: "journeyGPSStatus") }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse { start() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { stop(); status("Permissão de localização negada") }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status("GPS indisponível; distância pode estar incompleta")
        if let id = previousJourneyID {
            RadarEnvironment.distanceStore?.update { $0.record(journeyID: id, kilometers: 0, at: Date(), price: 0, consumption: 0, gap: true) }
        }
        previous = nil
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let now = Date()
        guard RadarEnvironment.sharedDefaults?.bool(forKey: "journeyGPSEnabled") == true else { stop(); return }
        guard let journey = RadarEnvironment.journeyStore?.load().active(at: now) else {
            previous = nil
            if let armedAt, now.timeIntervalSince(armedAt) > 60 { stop() }
            return
        }
        for location in locations {
            guard abs(now.timeIntervalSince(location.timestamp)) <= 15,
                  location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 35 else {
                status("GPS com precisão insuficiente; distância parcial")
                continue
            }
            if previousJourneyID != journey.id { previous = nil; previousJourneyID = journey.id }
            var kilometers = 0.0
            var gap = false
            if let previous {
                let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
                guard seconds > 0 else { continue }
                let meters = location.distance(from: previous)
                if RadarDistancePolicy.accepts(meters: meters, seconds: seconds,
                    accuracy: max(location.horizontalAccuracy, previous.horizontalAccuracy)) {
                    kilometers = meters / 1000
                } else if seconds > 60 || meters / seconds > 45 { gap = true }
                else if seconds >= 30 && meters < max(8, location.horizontalAccuracy * 0.5) {
                    self.previous = location
                }
                // Retain the previous anchor for small stationary GPS jitter.
                if kilometers > 0 || gap { self.previous = location }
            } else { previous = location; gap = location.timestamp.timeIntervalSince(journey.startedAt) > 30 }
            if kilometers > 0 || gap || now.timeIntervalSince(lastWrite) >= 15 {
                let defaults = RadarEnvironment.sharedDefaults
                RadarEnvironment.distanceStore?.update {
                    $0.record(journeyID: journey.id, kilometers: kilometers, at: location.timestamp,
                        price: defaults?.double(forKey: "fuelPricePerLiter") ?? 0,
                        consumption: defaults?.double(forKey: "fuelKilometersPerLiter") ?? 0, gap: gap)
                }
                lastWrite = now
            }
            status("GPS acompanhando a jornada; consumo estimado pelo preço e km/l configurados")
        }
    }
}
