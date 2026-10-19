import SwiftUI

// 云端模式主页：电脑不可达（外出/隧道断）时，经智谱官方中继派任务 + 看桌面任务。
// 两边各自出网连智谱云，消息由云端转交——不依赖局域网/隧道。
struct CloudHomeView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var mon = RelayMonitor.shared
    @State private var prompt = ""
    @State private var wsKey: String?
    @State private var sentTip = ""

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

                    VStack(alignment: .leading, spacing: 0) {
                        Text("桌面任务").font(.headline).padding(.bottom, 6)
                        let list = Array(mon.tasks.sorted { $0.updatedAt > $1.updatedAt }.prefix(20))
                        if list.isEmpty {
                            Text("暂无任务").font(.caption).foregroundColor(.secondary)
                        } else {
                            ForEach(list, id: \.id) { t in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.title).font(.subheadline).lineLimit(1)
                                        Text(relTime(t.updatedAt)).font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(statusText(t.status))
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
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)
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
    }

    private func relTime(_ ms: Int) -> String {
        guard ms > 0 else { return "" }
        let diff = (Date().timeIntervalSince1970 * 1000 - Double(ms)) / 1000
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(Int(diff / 60)) 分钟前" }
        if diff < 86400 { return "\(Int(diff / 3600)) 小时前" }
        return "\(Int(diff / 86400)) 天前"
    }
    private func statusText(_ s: String) -> String {
        switch s {
        case "running", "waiting": return "运行中"
        case "completed": return "已完成"
        case "error": return "出错"
        default: return s
        }
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
