import SwiftUI

// 云端模式的任务详情：经中继拉取会话消息，原生渲染 + 底部官方风格 composer（续聊）。
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
                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(msgs) { m in
                                            ForEach(m.blocks) { b in
                                                blockView(m, b)
                                                    .id(b.id)
                                            }
                                        }
                                    }
                                    .padding()
                                }
                                .onChange(of: mon.messages) { _ in
                                    withAnimation { proxy.scrollTo(lastBlockId(msgs), anchor: .bottom) }
                                }
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        proxy.scrollTo(lastBlockId(msgs), anchor: .bottom)
                                    }
                                }
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

    private var lastBlockId: (String) -> String {
        { msgs in
            let all = msgs.flatMap { $0.blocks.map { $0.id } }
            return all.last ?? (msgs.last?.id ?? "top")
        }
    }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespaces).isEmpty && !sending
    }

    private var modeLabel: String {
        switch task.mode {
        case "plan": return "只读规划"
        case "edit": return "允许改码"
        case "yolo": return "全自动"
        default: return task.mode?.isEmpty == false ? task.mode! : "跟随桌面"
        }
    }

    // 官方 composer 风格：圆角大容器，上输入、下控件行 + 黑色圆形发送键
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("续聊 / 追加要求…", text: $prompt, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "shield.lefthalf.filled")
                    Text(modeLabel).lineLimit(1)
                }
                .font(.caption2)
                .foregroundColor(task.mode == "yolo" ? .orange : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)
                if let m = task.modelId, !m.isEmpty {
                    Text(m)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(8)
                }
                Spacer()
                Button {
                    send()
                } label: {
                    Group {
                        if sending {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                        }
                    }
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(canSend ? Color.black : Color.black.opacity(0.25)))
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(18)
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
