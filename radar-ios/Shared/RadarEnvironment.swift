import Foundation

enum RadarEnvironment {
    static let originalGroup = "group.br.com.radaruber.app"

    // AltStore rewrites group IDs in each bundle's ALTAppGroups metadata.
    // Resolve only this app's group; never use an unrelated group.
    static func groupIdentifier(from metadata: [String: Any]) -> String {
        let groups = metadata["ALTAppGroups"] as? [String] ?? []
        return groups.first { $0 == originalGroup || $0.hasPrefix(originalGroup + ".") } ?? originalGroup
    }

    static let groupIdentifier = groupIdentifier(from: Bundle.main.infoDictionary ?? [:])
    #if os(Linux)
    // Linux CI validates the pure core without inventing an iOS App Group container.
    static let sharedContainerURL: URL? = nil
    #else
    static let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    #endif
    static var sharedContainerAvailable: Bool { sharedContainerURL != nil }
    static let journeyStore: RadarJourneyStore? = sharedContainerURL.map {
        RadarJourneyStore(url: $0.appendingPathComponent("journeys.json"))
    }
    static let distanceStore: RadarDistanceStore? = sharedContainerURL.map {
        RadarDistanceStore(url: $0.appendingPathComponent("distance-totals.json"))
    }
    static let paymentStore: RadarPaymentStore? = sharedContainerURL.map {
        RadarPaymentStore(url: $0.appendingPathComponent("payment-receipts.json"))
    }
    static let financeStore: RadarFinanceStore? = sharedContainerURL.map {
        RadarFinanceStore(url: $0.appendingPathComponent("finance-observations.json"))
    }
    static let readingStore: RadarReadingStore? = sharedContainerURL.map {
        RadarReadingStore(url: $0.appendingPathComponent("reading-status.json"))
    }
    static let sharedDefaults: UserDefaults? = {
        guard sharedContainerAvailable else { return nil }
        return UserDefaults(suiteName: groupIdentifier)
    }()
}

