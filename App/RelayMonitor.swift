import Foundation
import UIKit
import Combine

// 官方中继监控：把 ZCodeMobile 的 relay 接到本地通知上。
// 配对一次（粘贴/扫官方远控链接），后台走 zcode.z.ai 云中继收任务状态，
// 任何网络可用，不依赖电脑局域网/隧道。
// 注：不加 @MainActor——回调本就在主队列（session delegateQueue = .main），
// 非隔离类在 Swift 5 模式下编译风险最低。
final class RelayMonitor: ObservableObject {
    static let shared = RelayMonitor()

    let relay = OfficialRelay()

    @Published var officialURL: String = UserDefaults.standard.string(forKey: "officialURL") ?? "" {
        didSet { UserDefaults.standard.set(officialURL, forKey: "officialURL") }
    }
    @Published private(set) var stateLabel: String = "未连接"

    private var lastStatus: [String: String] = [:]
    /// 只在退后台期间活跃：前台让路给网页自己的官方远控连接（官方限制一路连接，避免互踢）
    private var active = false
    /// 挂起的重连定时器（去重，防止把已连上的连接踢掉重连）
    private var reconnectTimer: Timer?
    private var loginCancellable: AnyCancellable?

    /// 桌面上报的工作区（云派任务的选择列表）
    var workspaces: [OfficialRelay.WorkspaceInfo] { relay.workspaces }

    /// 桌面任务列表（云端模式主页用）
    var tasks: [TaskSummary] { relay.tasks }

    /// 工作区展示名：桌面端 label 是会话目录尾段（如 draft-xxx），不可读；
    /// 优先用该工作区最新任务的标题，让人一眼认出是哪个项目。
    func friendlyWorkspaceName(_ w: OfficialRelay.WorkspaceInfo) -> String {
        if let path = w.path {
            let latest = tasks
                .filter { ($0.workspacePath ?? "").caseInsensitiveCompare(path) == .orderedSame }
                .filter { !$0.title.isEmpty }
                .max { $0.updatedAt < $1.updatedAt }
            if let latest { return latest.title }
        }
        return (w.label ?? w.path ?? w.key) as String
    }

    /// 会话消息缓存（taskId → 消息流），任务详情页用
    @Published var messages: [String: [ChatMessage]] = [:]
    /// 最近一次派任务/发消息失败原因（nil = 正常），云派页据此提示
    @Published var lastSendError: String?

    var hasLink: Bool { OfficialLinkParser.parse(officialURL) != nil }

    private init() {
        relay.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed(let msg): self.stateLabel = "连接失败：" + msg
            default: self.stateLabel = state.label
            }
            self.objectWillChange.send()
            guard self.active else { return }
            if case .paired = state { self.reconnectTimer?.invalidate() }
            if case .idle = state { self.reconnectAfter(3) }
            if case .failed = state { self.reconnectAfter(10) }
        }
        relay.onSnapshot = { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
            self.diffAndNotify()
        }
        relay.onMessages = { [weak self] taskId, msgs in
            self?.messages[taskId] = msgs
            self?.objectWillChange.send()
        }
        // 派任务/发消息失败不再静默：云派页与详情页都能据此提示
        relay.onSendResult = { [weak self] ok, error in
            guard let self else { return }
            self.lastSendError = ok ? nil : (error ?? "发送失败")
        }
        // 账号登录成功后自动恢复连接（新版桌面 V2 配对缺登录时会失败挂起）
        loginCancellable = ZaiAccount.shared.$loginPhase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self, case .done = phase, self.active, self.hasLink else { return }
                if case .idle = self.relay.state { self.reconnectAfter(0.5) }
                if case .failed = self.relay.state { self.reconnectAfter(0.5) }
            }
    }

    /// 拉取某任务的会话消息（结果走 onMessages 回调）
    func loadMessages(_ taskId: String) {
        relay.loadMessages(for: taskId)
    }

    /// 前台临时接管中继（云派任务时用）
    func activateForDispatch() {
        active = true
        if relay.state == .idle, let link = OfficialLinkParser.parse(officialURL) {
            relay.connect(link)
        }
    }

    func refreshWorkspacesPub() {
        guard relay.state == .paired else { return }
        relay.refreshWorkspaces()
        objectWillChange.send()
    }

    /// 退后台：接管官方中继连接，开始收任务通知
    func activateInBackground() {
        guard hasLink else { return }
        active = true
        LocalNotify.request()
        if relay.state == .idle, let link = OfficialLinkParser.parse(officialURL) {
            relay.connect(link)
        }
    }

    /// 回前台：断开中继，把连接让给网页（如果网页里开着官方远控）
    func deactivate() {
        active = false
        if relay.state != .idle { relay.disconnect() }
    }

    func connect(from raw: String) {
        officialURL = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let link = OfficialLinkParser.parse(officialURL) {
            relay.connect(link)
        }
    }

    func disconnectAll() {
        officialURL = ""
        relay.disconnect()
        stateLabel = "未连接"
    }

    private func reconnectAfter(_ seconds: TimeInterval) {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self, self.active, self.hasLink else { return }
            // V2 未登录时不自动重试（失败文案会引导去设置登录；登录成功由 loginCancellable 触发重连）
            if let link = OfficialLinkParser.parse(self.officialURL), link.isV2, !ZaiAccount.shared.isLoggedIn {
                return
            }
            switch self.relay.state {
            case .idle, .failed:
                if let link = OfficialLinkParser.parse(self.officialURL) {
                    self.relay.connect(link)
                }
            default:
                break
            }
        }
    }

    // 任务状态 diff：运行中 → 完成/出错，且 90 秒内的新鲜变化才弹（防重连后轰炸）
    private func diffAndNotify() {
        let previous = lastStatus
        let now = Date().timeIntervalSince1970 * 1000
        for task in relay.tasks {
            let old = previous[task.id]
            lastStatus[task.id] = task.status
            guard let old, old != task.status else { continue }
            guard old == "running" || old == "waiting",
                  task.status == "completed" || task.status == "error" else { continue }
            let fresh = task.updatedAt > 0 && (now - Double(task.updatedAt)) < 90_000
            guard fresh else { continue }
            if task.status == "completed" {
                LocalNotify.fire(title: "✅ 任务完成", body: task.title, taskId: task.id)
                pushBark(title: "✅ 任务完成", body: task.title)
            } else {
                LocalNotify.fire(title: "❌ 任务出错", body: task.title, taskId: task.id)
                pushBark(title: "❌ 任务出错", body: task.title)
            }
        }
    }

    /// Bark 双保险：App 进程被杀时系统通知不可靠，经 Bark 服务器再推一份
    private func pushBark(title: String, body: String) {
        guard AppSettings.barkEnabled else { return }
        var base = AppSettings.barkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard base.lowercased().hasPrefix("http") else { return }
        if base.hasSuffix("/") { base.removeLast() }
        let enc = { (s: String) -> String in
            s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
        }
        guard let url = URL(string: "\(base)/\(enc(title))/\(enc(body))?group=Pocket") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }
}
