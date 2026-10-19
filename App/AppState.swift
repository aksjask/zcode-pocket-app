import Foundation
import Combine
import WebKit

final class AppState: ObservableObject {
    static let shared = AppState()

    /// 配置好的服务器地址；为空表示首次启动，先进设置页
    @Published var serverURL: String = AppSettings.serverURL {
        didSet { AppSettings.serverURL = serverURL }
    }
    var configured: Bool { AppSettings.isValid }

    @Published var showSettings = false
    @Published var showRelayCompose = false
    @Published var isLoading = false
    weak var webView: WKWebView?

    func reload() {
        guard let url = URL(string: serverURL), AppSettings.isValid else { return }
        if let wv = webView {
            wv.load(URLRequest(url: url))
        }
    }

    func save(url raw: String) -> String? {
        var u = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty { return "地址不能为空" }
        if !u.lowercased().hasPrefix("http://") && !u.lowercased().hasPrefix("https://") {
            u = "http://" + u
        }
        guard let url = URL(string: u), url.host != nil else { return "地址格式不对" }
        serverURL = u
        return nil
    }

    // ---- 前后台切换 ----
    // 后台：静音保活 + 桥接轮询 + 官方中继接管（双通道通知）
    // 前台：停掉保活/轮询，中继让路给网页里的官方远控连接
    func handleBackground() {
        guard configured else { return }
        SilentAudio.shared.start()
        TaskWatcher.shared.start()
        RelayMonitor.shared.activateInBackground()
    }

    func handleForeground() {
        SilentAudio.shared.stop()
        TaskWatcher.shared.stop()
        RelayMonitor.shared.deactivate()
    }

    /// 点通知直达对应会话：让网页自己跳 #job= 深链
    func openTask(_ taskId: String) {
        guard var comps = URLComponents(string: serverURL) else { return }
        comps.fragment = "job=" + taskId
        guard let url = comps.string, let u = URL(string: url) else { return }
        if let wv = webView {
            wv.load(URLRequest(url: u))
        }
    }
}
