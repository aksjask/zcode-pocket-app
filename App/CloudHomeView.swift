import SwiftUI

// 云端模式主页：电脑不可达（外出/隧道断）时，经智谱官方中继派任务 + 看桌面任务。
// 两边各自出网连智谱云，消息由云端转交——不依赖局域网/隧道。
// 桌面任务支持「# 分组 / 📁 项目」双视图（对照桌面 ZCode 侧栏）。
struct CloudHomeView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var mon = RelayMonitor.shared
    @AppStorage("zp_cloudview") private var viewMode = "group"
    @State private var prompt = ""
    @State private var wsKey: String?
    @State private var sentTip = ""
    @State private var expanded: Set<String> = []
    @State private var selected: TaskSummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "cloud.fill").foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("云端模式").font(.headline)
                        Text(mon.hasLink ? "中继：\(mon.stateLabel) · 消息经智谱云转交" : "未配对官方远控：去设置粘贴远控链接")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("重试电脑") { state.checkServerReachability() }
                        .font(.caption)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(14)

                if mon.hasLink {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("派任务给桌面 ZCode").font(.headline)
                        if mon.relay.state != .paired {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("连接智谱云中（\(mon.stateLabel)）…").font(.caption).foregroundColor(.secondary)
                            }
                        } else if mon.workspaces.isEmpty {
                            Text("桌面还没上报工作区，稍等几秒，或回桌面确认 ZCode 已打开。")
                                .font(.caption).foregroundColor(.secondary)
                        } else {
                            Picker("工作区", selection: $wsKey) {
                                ForEach(mon.workspaces, id: \.key) { w in
                                    Text(w.label ?? w.path ?? w.key).tag(Optional(w.key))
                                }
                            }
                            .onChange(of: wsKey) { newValue in
                                mon.relay.useWorkspace(newValue)
                            }
                            TextField("要做什么…", text: $prompt, axis: .vertical)
                                .lineLimit(3...6)
                            Button {
                                let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !text.isEmpty else { return }
                                mon.relay.useWorkspace(wsKey)
                                mon.relay.startNewChat(firstInput: text)
                                prompt = ""
                                sentTip = "已派出 ✓"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { sentTip = "" }
                            } label: {
                                Text("经官方云派出").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                            if !sentTip.isEmpty {
                                Text(sentTip).font(.caption).foregroundColor(.green)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)

                    // ---- 双视图切换 ----
                    Picker("视图", selection: $viewMode) {
                        Text("# 分组").tag("group")
                        Text("📁 项目").tag("project")
                    }
                    .pickerStyle(.segmented)

                    if viewMode == "group" {
                        groupView
                    } else {
                        projectView
                    }
                }
                Text("连回家里 WiFi 后点「重试电脑」，可回到完整 Pocket 网页（历史/统计/精确派活）。")
                    .font(.caption2).foregroundColor(.secondary)
            }
            .padding()
        }
        .onAppear {
            mon.activateForDispatch()
            mon.refreshWorkspacesPub()
        }
        .sheet(item: $selected) { t in
            TaskDetailView(task: t)
        }
    }

    // 当前排序后的全部任务
    private var sortedTasks: [TaskSummary] {
        let pin = mon.tasks.filter { $0.pinned }.sorted { $0.updatedAt > $1.updatedAt }
        let rest = mon.tasks.filter { !$0.pinned }.sorted { $0.updatedAt > $1.updatedAt }
        return pin + rest
    }

    /// 「# 分组」：置顶在前 + 扁平列表
    private var groupView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("桌面任务").font(.headline).padding(.bottom, 6)
            let list = Array(sortedTasks.prefix(25))
            if list.isEmpty {
                Text("暂无任务").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(list, id: \.id) { t in
                    taskRow(t)
                        .contentShape(Rectangle())
                        .onTapGesture { selected = t }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }

    /// 「📁 项目」：按工作区分格折叠
    private var projectView: some View {
        let groups = Dictionary(grouping: mon.tasks) { t in
            (t.workspacePath ?? "").isEmpty ? "其他" : (t.workspacePath ?? "其他")
        }
        let order = groups.keys.sorted { a, b in
            let ma = groups[a]!.map { $0.updatedAt }.max() ?? 0
            let mb = groups[b]!.map { $0.updatedAt }.max() ?? 0
            return ma > mb
        }
        return VStack(alignment: .leading, spacing: 10) {
            if order.isEmpty {
                Text("暂无任务").font(.caption).foregroundColor(.secondary)
            }
            ForEach(order, id: \.self) { key in
                let list = (groups[key] ?? []).sorted { $0.updatedAt > $1.updatedAt }
                let hasRunning = list.contains { $0.isRunning }
                DisclosureGroup(isExpanded: bindingFor(key)) {
                    ForEach(list, id: \.id) { t in
                        taskRow(t)
                            .contentShape(Rectangle())
                            .onTapGesture { selected = t }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(displayName(key)).font(.subheadline).fontWeight(.semibold).lineLimit(1)
                        if hasRunning { Circle().fill(Color.blue).frame(width: 7, height: 7) }
                        Spacer()
                        Text("\(list.count) 任务").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }

    private func bindingFor(_ key: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(key) || mon.tasks.count <= 15 },
            set: { if $0 { expanded.insert(key) } else { expanded.remove(key) } }
        )
    }

    private func displayName(_ path: String) -> String {
        if path == "其他" { return "其他" }
        // 云端模式拿不到电脑配置里的工作区昵称，用路径末段
        return (path as NSString).lastPathComponent
    }

    private func taskRow(_ t: TaskSummary) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title).font(.subheadline).lineLimit(1)
                    Text(relTime(t.updatedAt)).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Text(t.statusLabel)
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusColor(t.status).opacity(0.18))
                    .foregroundColor(statusColor(t.status))
                    .cornerRadius(8)
            }
            .padding(.vertical, 6)
            Divider()
        }
    }

    private func relTime(_ ms: Int) -> String {
        guard ms > 0 else { return "" }
        let diff = (Date().timeIntervalSince1970 * 1000 - Double(ms)) / 1000
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(Int(diff / 60)) 分钟前" }
        if diff < 86400 { return "\(Int(diff / 3600)) 小时前" }
        return "\(Int(diff / 86400)) 天前"
    }
    private func statusColor(_ s: String) -> Color {
        switch s {
        case "running", "waiting": return .blue
        case "completed": return .green
        case "error": return .red
        default: return .gray
        }
    }
}
