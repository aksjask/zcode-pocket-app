import SwiftUI
import UIKit
import UserNotifications

@main
struct PocketApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotifyDelegate.shared
        // 点通知直达对应会话：让 Pocket 网页跳 #job= 深链（网页端已支持）
        NotifyDelegate.shared.onOpenTask = { taskId in
            DispatchQueue.main.async {
                AppState.shared.openTask(taskId)
            }
        }
        return true
    }
}
