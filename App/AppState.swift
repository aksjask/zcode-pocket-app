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
    @Published var cloudMode = false
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
    // 前台：停掉保活/轮询；云端模式下中继保持，网页模式下让路
    func handleForeground() {
        SilentAudio.shared.stop()
        TaskWatcher.shared.stop()
        if cloudMode {
            RelayMonitor.shared.activateForDispatch()
        } else {
            RelayMonitor.shared.deactivate()
        }
        checkServerReachability()
    }

    /// 探测电脑可达性：连不上自动进云端模式，恢复了自动回网页模式
    func checkServerReachability() {
        guard configured, let url = URL(string: serverURL) else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, err in
            let ok = (err == nil && (resp as? HTTPURLResponse) != nil)
            DispatchQueue.main.async {
                guard let self else { return }
                if ok {
                    if self.cloudMode { self.exitCloudMode() }
                } else if !self.cloudMode {
                    self.enterCloudMode()
                }
            }
        }.resume()
    }

    func enterCloudMode() {
        cloudMode = true
        RelayMonitor.shared.activateForDispatch()
        RelayMonitor.shared.refreshWorkspacesPub()
    }

    func exitCloudMode() {
        cloudMode = false
        RelayMonitor.shared.deactivate()
        reload()
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
