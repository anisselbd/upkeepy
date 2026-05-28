import Foundation
import UserNotifications

/// Gestion des notifications système (cadre `UserNotifications`).
/// L'utilisateur voit la première demande de permission au premier lancement.
enum Notifications {

    /// Demande l'autorisation si l'utilisateur n'a pas encore tranché.
    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationsDelegate.shared
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Envoie une notification immédiate. Silencieux si la permission a été refusée.
    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

/// Force l'affichage de la bannière même quand UpKeepy est l'app active
/// (menu bar app → souvent considérée comme « au premier plan »).
private final class NotificationsDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsDelegate()
    private override init() { super.init() }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
