import AppKit
import GrokBuildStatusCore
import UserNotifications

@MainActor
final class StatusNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = StatusNotifications()

    var onOpenSession: ((String) -> Void)?

    private static let enabledKey = "notificationsEnabled"

    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
        }
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    func setEnabled(_ enabled: Bool, completion: @escaping (Bool) -> Void) {
        if enabled {
            Task { @MainActor in
                let granted = await self.authorize()
                self.isEnabled = granted
                completion(granted)
            }
        } else {
            isEnabled = false
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
            completion(true)
        }
    }

    func post(_ alerts: [SessionAlert]) {
        guard isEnabled, !alerts.isEmpty else { return }
        Task { @MainActor in
            let granted = await self.authorize()
            if !granted {
                self.isEnabled = false
                return
            }
            for alert in alerts {
                self.deliver(alert)
            }
        }
    }

    private func authorize() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied:
            return false
        default:
            return (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    private func deliver(_ alert: SessionAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.body
        content.sound = .default
        content.userInfo = ["sessionId": alert.sessionId]
        let identifier = "\(alert.sessionId).\(alert.light.name)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.content.userInfo["sessionId"] as? String
        Task { @MainActor in
            if let id {
                StatusNotifications.shared.onOpenSession?(id)
            }
        }
        completionHandler()
    }
}
