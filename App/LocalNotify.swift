import Foundation
import UserNotifications
import UIKit

enum LocalNotify {
    /// 双通道去重：同一任务同一状态 5 分钟内只弹一次（TaskWatcher 和 RelayMonitor 会看到同一个桌面任务）
    private static var recent: [String: Date] = [:]
    private static let lock = NSLock()

    static func request() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func fire(title: String, body: String, taskId: String?) {
        lock.lock()
        let gate = "\(taskId ?? "-")|\(title)"
        if let last = recent[gate], Date().timeIntervalSince(last) < 300 {
            lock.unlock()
            return
        }
        recent[gate] = Date()
        if recent.count > 200 {
            let cutoff = Date().addingTimeInterval(-600)
            recent = recent.filter { $0.value > cutoff }
        }
        lock.unlock()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let taskId {
            content.userInfo = ["taskId": taskId]
        }
        let request = UNNotificationRequest(
            identifier: "pocket-\(taskId ?? UUID().uuidString)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber += 1
        }
    }
}

final class NotifyDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifyDelegate()
    var onOpenTask: ((String) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 前台也弹横幅，行为和 Bark 一致
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let taskId = response.notification.request.content.userInfo["taskId"] as? String {
            onOpenTask?(taskId)
        }
        completionHandler()
    }
}
