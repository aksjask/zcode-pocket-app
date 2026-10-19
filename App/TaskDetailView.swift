import SwiftUI

// 云端模式的任务详情：经中继拉取会话消息，原生渲染 + 底部续聊输入框。
struct TaskDetailView: View {
    @ObservedObject var mon = RelayMonitor.shared
    let task: TaskSummary
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var sending = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Group {
                    if mon.relay.state != .paired {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("连接智谱云中（\(mon.stateLabel)）…").font(.footnote).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        let msgs = mon.messages[task.id] ?? []
                        if msgs.isEmpty {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text("正在拉取会话消息…").font(.footnote).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(msgs) { m in
                                        ForEach(m.blocks) { b in
                                            blockView(m, b)
                                        }
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                composer
            }
            .navigationTitle(task.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if task.isRunning {
                        Button("停止") { mon.relay.stopTask(task.id) }
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .onAppear {
            mon.activateForDispatch()
            mon.loadMessages(task.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { mon.loadMessages(task.id) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { mon.loadMessages(task.id) }
        }
    }

    // 底部续聊输入框：经中继转给桌面会话
    private var composer: some View {
        HStack(spacing: 8) {
            TextField("续聊 / 追加要求…", text: $prompt, axis: .vertical)
                .lineLimit(1...4)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            Button {
                send()
            } label: {
                if sending {
                    ProgressView().frame(width: 26)
                } else {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(prompt.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .accentColor)
                }
            }
            .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || sending)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        prompt = ""
        sending = true
        mon.relay.sendText(text, taskId: task.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            mon.loadMessages(task.id)
            sending = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { mon.loadMessages(task.id) }
    }

    @ViewBuilder private func blockView(_ m: ChatMessage, _ b: ChatBlock) -> some View {
        switch b.kind {
        case "text":
            HStack(alignment: .top) {
                if m.isUser { Spacer(minLength: 44) }
                Text(b.text)
                    .font(.subheadline)
                    .padding(10)
                    .background(m.isUser ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                    .cornerRadius(12)
                if !m.isUser { Spacer(minLength: 44) }
            }
        case "tool":
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver").font(.caption2)
                Text(b.tool ?? "工具").font(.caption)
                if let p = b.path { Text(p).font(.caption2).lineLimit(1).foregroundColor(.secondary) }
            }
            .foregroundColor(.secondary)
        default:
            EmptyView()
        }
    }
}
