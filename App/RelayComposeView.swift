import SwiftUI

// 经官方中继派任务：任务在桌面 ZCode 里执行，任何网络可用（走 zcode.z.ai 云）。
// 前台临时接管中继连接，关页即让路（官方限制一路连接）。
struct RelayComposeView: View {
    @ObservedObject var mon = RelayMonitor.shared
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var wsKey: String?
    @State private var sent = false

    var body: some View {
        NavigationView {
            Form {
                if !mon.hasLink {
                    Section {
                        Text("还没有配对官方远控。先到「设置 → 官方远控链接」粘贴电脑 ZCode 的远程控制链接。")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                } else if mon.relay.state != .paired {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在连接官方云（\(mon.stateLabel)）…").font(.footnote).foregroundColor(.secondary)
                        }
                    }
                } else {
                    Section("目标工作区（桌面已打开的）") {
                        if mon.workspaces.isEmpty {
                            Text("桌面还没有上报工作区，稍等几秒，或回桌面确认 ZCode 已打开。")
                                .font(.footnote).foregroundColor(.secondary)
                        } else {
                            Picker("工作区", selection: $wsKey) {
                                ForEach(mon.workspaces, id: \.key) { w in
                                    Text(w.label ?? w.path ?? w.key).tag(Optional(w.key))
                                }
                            }
                            .onChange(of: wsKey) { newValue in
                                mon.relay.useWorkspace(newValue)
                            }
                        }
                    }
                    Section("要做什么") {
                        TextField("例如：把首页的按钮都换成圆角", text: $prompt, axis: .vertical)
                            .lineLimit(4...8)
                    }
                    Section {
                        Button {
                            let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return }
                            mon.relay.useWorkspace(wsKey)
                            mon.relay.startNewChat(firstInput: text)
                            sent = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
                        } label: {
                            Text(sent ? "已派出 ✓（完成会弹通知）" : "经官方云派出")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || sent)
                    }
                    Section {
                        Text("任务在电脑桌面 ZCode 里执行、桌面可见；派出后 App 退到后台会继续盯状态，完成/出错弹横幅。权限模式跟桌面当前设置走。")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("云派任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onAppear {
            mon.activateForDispatch()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { mon.refreshWorkspacesPub() }
        }
        .onDisappear { mon.deactivate() }
    }
}
