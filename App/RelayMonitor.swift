import Foundation
import UIKit

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

    /// 桌面上报的工作区（云派任务的选择列表）
    var workspaces: [OfficialRelay.WorkspaceInfo] { relay.workspaces }

    /// 桌面任务列表（云端模式主页用）
    var tasks: [OfficialRelay.TaskSummary] { relay.tasks }

    var hasLink: Bool { OfficialLinkParser.parse(officialURL) != nil }

    private init() {
        relay.onStateChange = { [weak self] state in
            self?.stateLabel = state.label
            self?.objectWillChange.send()
            guard let self, self.active else { return }
            if case .idle = state { self.reconnectAfter(3) }
            if case .failed = state { self.reconnectAfter(10) }
        }
        relay.onSnapshot = { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
            self.diffAndNotify()
        }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.active, self.hasLink else { return }
            if case .idle = self.relay.state {
                if let link = OfficialLinkParser.parse(self.officialURL) {
                    self.relay.connect(link)
                }
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
            } else {
                LocalNotify.fire(title: "❌ 任务出错", body: task.title, taskId: task.id)
            }
        }
    }
}
