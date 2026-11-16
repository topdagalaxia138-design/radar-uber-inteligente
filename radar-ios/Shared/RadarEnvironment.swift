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
    static var sharedContainerAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) != nil
    }
    static var sharedDefaults: UserDefaults? {
        guard sharedContainerAvailable else { return nil }
        return UserDefaults(suiteName: groupIdentifier)
    }
}
