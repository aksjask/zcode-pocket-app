import SwiftUI

// 云端模式主页：电脑不可达时经智谱官方中继派任务 + 看桌面任务。
// 深色风格对齐官方 ZCode App（工作区卡 / 任务卡 / 已置顶 / 双视图）。
struct CloudHomeView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var mon = RelayMonitor.shared
    @AppStorage("zp_cloudview") private var viewMode = "group"
    @State private var prompt = ""
    @State private var wsKey: String?
    @State private var sentTip = ""
    @State private var expanded: Set<String> = []
    @State private var selected: TaskSummary?
    @State private var inlineComposeFor: String?
    @State private var sending = false

    private var sortedTasks: [TaskSummary] {
        let pin = mon.tasks.filter { $0.pinned }.sorted { $0.updatedAt > $1.updatedAt }
        let rest = mon.tasks.filter { !$0.pinned }.sorted { $0.updatedAt > $1.updatedAt }
        return pin + rest
    }

    private let bg = Color.black
    private let card = Color(red: 0.075, green: 0.078, blue: 0.09)
    private let border = Color.white.opacity(0.09)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                banner
                headerRow
                viewToggle
                composeCard
                if viewMode == "group" {
                    groupSections
                } else {
                    projectSections
                }
                Text("连回家里 WiFi 后点顶部「重试电脑」，回到完整 Pocket 网页。")
                    .font(.caption2).foregroundColor(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 30)
        }
        .background(bg)
        .preferredColorScheme(.dark)
        .onAppear {
            mon.activateForDispatch()
            mon.refreshWorkspacesPub()
        }
        .sheet(item: $selected) { t in
            TaskDetailView(task: t)
        }
    }

    // ---------- 顶部 ----------

    private var banner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("云端模式 · 消息经智谱云转交").font(.subheadline).fontWeight(.medium)
            Text(mon.hasLink
                 ? "中继：\(mon.stateLabel)。派任务、盯状态全走官方中继，电脑不可达时可用。"
                 : "未配对官方远控：先到设置粘贴电脑 ZCode 的远程控制链接。")
                .font(.caption).foregroundColor(.white.opacity(0.5))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border))
        .overlay(alignment: .topTrailing) {
            Button("重试电脑") { state.checkServerReachability() }
                .font(.caption2).foregroundColor(.white.opacity(0.5))
                .padding(8)
        }
    }

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("桌面任务（官方中继）").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
            Text("\(wsCount) 个工作区 · \(mon.tasks.count) 个任务").font(.footnote).foregroundColor(.white.opacity(0.5))
        }
    }

    private var wsCount: Int {
        Set(mon.tasks.map { $0.workspacePath ?? "" }).count
    }

    private var viewToggle: some View {
        HStack(spacing: 8) {
            toggleBtn("# 分组", "group")
            toggleBtn("📁 项目", "project")
            Spacer()
        }
    }

    private func toggleBtn(_ title: String, _ mode: String) -> some View {
        Button {
            viewMode = mode
        } label: {
            Text(title)
                .font(.system(size: 13, weight: viewMode == mode ? .semibold : .regular))
                .foregroundColor(viewMode == mode ? .white : .white.opacity(0.5))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(viewMode == mode ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
                .cornerRadius(9)
        }
    }

    // ---------- 派任务卡（官方 composer 风格） ----------

    private var composeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("要做什么…", text: $prompt, axis: .vertical)
                .lineLimit(1...4)
                .font(.subheadline)
            HStack(spacing: 8) {
                Menu {
                    ForEach(mon.workspaces, id: \.key) { w in
                        Button(w.label ?? w.path ?? w.key) { wsKey = w.key }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text(wsSelectedName).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
                }
                Spacer()
                if !sentTip.isEmpty {
                    Text(sentTip).font(.caption2).foregroundColor(.green)
                }
                Button {
                    send()
                } label: {
                    Group {
                        if sending { ProgressView().tint(.black) } else { Image(systemName: "arrow.up") }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(canSend ? Color(white: 0.85) : Color(white: 0.85).opacity(0.35)))
                }
                .disabled(!canSend)
            }
        }
        .padding(12)
        .background(card)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(border))
    }

    private var wsSelectedName: String {
        if let wsKey, let w = mon.workspaces.first(where: { $0.key == wsKey }) {
            return (w.label ?? w.path ?? w.key) as String
        }
        return mon.workspaces.first.map { ($0.label ?? $0.path ?? $0.key) as String } ?? "选工作区"
    }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespaces).isEmpty && !sending && mon.relay.state == .paired
    }

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        prompt = ""
        sending = true
        mon.relay.useWorkspace(wsKey)
        mon.relay.startNewChat(firstInput: text)
        sentTip = "已派出 ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { sentTip = ""; sending = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { mon.refreshWorkspacesPub() }
    }

    // ---------- 「# 分组」视图 ----------

    private var groupSections: some View {
        VStack(alignment: .leading, spacing: 8) {
            let pinned = sortedTasks.filter { $0.pinned }
            let rest = sortedTasks.filter { !$0.pinned }
            if !pinned.isEmpty {
                sectionLabel("已置顶")
                ForEach(pinned, id: \.id) { taskCard($0) }
            }
            sectionLabel("历史会话")
            if rest.isEmpty && pinned.isEmpty {
                Text("暂无任务，上方输入即可经官方云派出。").font(.caption).foregroundColor(.white.opacity(0.4))
            } else {
                ForEach(rest.prefix(40), id: \.id) { taskCard($0) }
            }
        }
    }

    // ---------- 「📁 项目」视图 ----------

    private var projectSections: some View {
        let groups = Dictionary(grouping: mon.tasks) { t in
            (t.workspacePath ?? "").isEmpty ? "其他" : (t.workspacePath ?? "其他")
        }
        let order = groups.keys.sorted { a, b in
            let ma = groups[a]!.map { $0.updatedAt }.max() ?? 0
            let mb = groups[b]!.map { $0.updatedAt }.max() ?? 0
            return ma > mb
        }
        return VStack(spacing: 10) {
            if order.isEmpty {
                Text("暂无任务").font(.caption).foregroundColor(.white.opacity(0.4))
            }
            ForEach(order, id: \.self) { key in
                wsCard(key: key, list: (groups[key] ?? []).sorted { $0.updatedAt > $1.updatedAt })
            }
        }
    }

    private func wsCard(key: String, list: [TaskSummary]) -> some View {
        let hasRunning = list.contains { $0.isRunning }
        let isOpen = expanded.contains(key)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                folderIcon
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(wsShortName(key)).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        Text("本地").font(.caption2).foregroundColor(.white.opacity(0.45))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.white.opacity(0.08)).cornerRadius(6)
                    }
                    Text(pathShort(key)).font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4)).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    if hasRunning { Circle().fill(Color.blue).frame(width: 7, height: 7).frame(maxWidth: .infinity, alignment: .trailing) }
                    HStack(spacing: 2) {
                        Text("\(list.count) 个任务").font(.caption).foregroundColor(.white.opacity(0.6))
                        Image(systemName: "chevron.right").font(.caption2).foregroundColor(.white.opacity(0.4))
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                    }
                }
                Button {
                    inlineComposeFor = (inlineComposeFor == key) ? nil : key
                    wsKey = key
                } label: {
                    Image(systemName: "plus").font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                }
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isOpen { expanded.remove(key) } else { expanded.insert(key) }
                }
            }
            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(list.prefix(30), id: \.id) { t in
                        taskRow(t)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
            }
            if inlineComposeFor == key {
                HStack(spacing: 8) {
                    TextField("在这个项目里要做什么…", text: $prompt, axis: .vertical)
                        .lineLimit(1...3).font(.subheadline)
                        .padding(8).background(Color.white.opacity(0.07)).cornerRadius(10)
                    Button {
                        sendInline(key)
                    } label: {
                        Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7).fill(canSend ? Color(white: 0.85) : Color(white: 0.85).opacity(0.35)))
                    }
                    .disabled(!canSend)
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
            Text("更新于 \(relTime(list.map { $0.updatedAt }.max() ?? 0))")
                .font(.caption2).foregroundColor(.white.opacity(0.4))
                .padding(.leading, 62).padding(.bottom, 10)
        }
        .background(card)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border))
    }

    private func taskTitle(_ t: TaskSummary) -> String {
        t.title.isEmpty ? "（无标题）" : t.title
    }

    private func taskRow(_ t: TaskSummary) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(taskTitle(t)).font(.system(size: 14.5)).foregroundColor(.white).lineLimit(2)
                Text(relTime(t.updatedAt)).font(.caption2).foregroundColor(.white.opacity(0.45))
            }
            Spacer()
            statusPill(t.status)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { selected = t }
    }

    private func taskCard(_ t: TaskSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if t.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11))
                    .foregroundColor(t.isRunning ? .blue : .white.opacity(0.45))
                    .padding(.top, 3)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(taskTitle(t)).font(.system(size: 15)).foregroundColor(.white).lineLimit(2)
                Text("桌面 · \(relTime(t.updatedAt))")
                    .font(.caption).foregroundColor(.white.opacity(0.45))
            }
            Spacer()
            statusPill(t.status)
        }
        .padding(12)
        .background(card)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border))
        .contentShape(Rectangle())
        .onTapGesture { selected = t }
    }

    private var folderIcon: some View {
        Image(systemName: "folder")
            .font(.system(size: 16))
            .foregroundColor(.white.opacity(0.6))
            .frame(width: 40, height: 40)
            .background(Color.white.opacity(0.07))
            .cornerRadius(11)
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.5))
            .padding(.top, 4)
    }

    private func statusPill(_ s: String) -> some View {
        let (text, color): (String, Color) = {
            switch s {
            case "running", "waiting": return ("运行中", .blue)
            case "completed": return ("已完成", .green)
            case "error": return ("错误", .red)
            default: return (s, .gray)
            }
        }()
        return HStack(spacing: 3) {
            Image(systemName: s == "completed" ? "checkmark.circle.fill" : s == "error" ? "exclamationmark.circle.fill" : "circle.dotted")
            Text(text)
        }
        .font(.caption2)
        .foregroundColor(color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.16))
        .cornerRadius(9)
    }

    // ---------- 工具 ----------

    private func sendInline(_ key: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        prompt = ""
        sending = true
        mon.relay.useWorkspace(key)
        mon.relay.startNewChat(firstInput: text)
        sentTip = "已派出 ✓"
        inlineComposeFor = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { sentTip = ""; sending = false }
    }

    private func wsShortName(_ path: String) -> String {
        path == "其他" ? "其他" : (path as NSString).lastPathComponent
    }
    private func pathShort(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
    }
    private func relTime(_ ms: Int) -> String {
        guard ms > 0 else { return "" }
        let diff = (Date().timeIntervalSince1970 * 1000 - Double(ms)) / 1000
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(Int(diff / 60)) 分钟" }
        if diff < 86400 { return "\(Int(diff / 3600)) 小时" }
        return "\(Int(diff / 86400)) 天"
    }
}
