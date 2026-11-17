import Foundation
#if os(iOS)
import UserNotifications
#endif

enum RadarNotifications {
    static let offerCategory = "RADAR_OFFER"
    static let testCategory = "RADAR_TEST"

    #if os(iOS)
    // This prepares notification delivery only. A supported, Apple-approved
    // CarPlay app/profile and device permission are still required.
    static func configure(_ center: UNUserNotificationCenter) {
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: offerCategory, actions: [],
                intentIdentifiers: [], options: [.allowInCarPlay]),
            UNNotificationCategory(identifier: testCategory, actions: [],
                intentIdentifiers: [], options: [.allowInCarPlay])
        ]
        center.setNotificationCategories(categories)
        center.requestAuthorization(options: [.alert, .sound, .badge, .carPlay]) { _, _ in }
    }
    #endif
}

enum RadarCarPlayAvailability {
    case enabled, disabled, unsupported

    var message: String {
        switch self {
        case .enabled:
            return "O iOS permite avisos no CarPlay; exibição ainda precisa ser testada na central."
        case .disabled:
            return "Avisos no CarPlay desativados. Confira os ajustes de notificações do Radar."
        case .unsupported:
            return "CarPlay indisponível nesta instalação. A preparação dos avisos não substitui a aprovação e assinatura exigidas pela Apple."
        }
    }
}
