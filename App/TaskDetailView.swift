import SwiftUI

// 云端模式的任务会话页：经中继拉取会话消息，官方深色风格渲染 + 底部 composer 续聊。
struct TaskDetailView: View {
    @ObservedObject var mon = RelayMonitor.shared
    let task: TaskSummary
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var sending = false

    private let bg = Color.black
    private let composerBg = Color(red: 0.10, green: 0.10, blue: 0.12)

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Group {
                    if mon.relay.state != .paired {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("连接智谱云中（\(mon.stateLabel)）…").font(.footnote).foregroundColor(.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        let msgs = mon.messages[task.id] ?? []
                        if msgs.isEmpty {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text("正在拉取会话消息…").font(.footnote).foregroundColor(.white.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 14) {
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
                                    withAnimation { proxy.scrollTo(lastId(msgs), anchor: .bottom) }
                                }
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        proxy.scrollTo(lastId(msgs), anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                composer
            }
            .background(bg)
            .navigationTitle(task.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.foregroundColor(.white)
                }
                ToolbarItem(placement: .primaryAction) {
                    if task.isRunning {
                        Button("停止") { mon.relay.stopTask(task.id) }
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            mon.activateForDispatch()
            mon.loadMessages(task.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { mon.loadMessages(task.id) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { mon.loadMessages(task.id) }
        }
    }

    private func lastId(_ msgs: [ChatMessage]) -> String {
        msgs.last?.blocks.last?.id ?? msgs.last?.id ?? "top"
    }

    // 官方 composer：深色圆角容器，上行输入，下行 + 盾牌(橙) … 🧠 + 方块↑
    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("提出后续修改要求", text: $prompt, axis: .vertical)
                .lineLimit(1...5)
                .font(.subheadline)
                .foregroundColor(.white)
            HStack(spacing: 12) {
                Image(systemName: "plus").font(.system(size: 15)).foregroundColor(.white.opacity(0.55))
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 13))
                    .foregroundColor(task.mode == "yolo" ? .orange : .white.opacity(0.55))
                Spacer()
                if sending {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "brain.head.profile").font(.system(size: 13)).foregroundColor(.white.opacity(0.45))
                }
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(canSend ? Color(white: 0.85) : Color(white: 0.85).opacity(0.35)))
                }
                .disabled(!canSend)
            }
        }
        .padding(12)
        .background(composerBg)
        .cornerRadius(18)
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespaces).isEmpty && !sending
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

    // 消息块：assistant 白字正文；user 右侧气泡；tool 暗灰活动行
    @ViewBuilder private func blockView(_ m: ChatMessage, _ b: ChatBlock) -> some View {
        switch b.kind {
        case "text":
            if m.isUser {
                HStack(alignment: .top) {
                    Spacer(minLength: 52)
                    Text(b.text)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color(red: 0.16, green: 0.19, blue: 0.27))
                        .cornerRadius(12)
                }
            } else {
                Text(b.text)
                    .font(.system(size: 15.5))
                    .foregroundColor(Color(white: 0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case "tool":
            toolRow(b)
        default:
            EmptyView()
        }
    }

    private func toolRow(_ b: ChatBlock) -> some View {
        let info = toolInfo(b.tool)
        return HStack(spacing: 6) {
            Image(systemName: info.icon).font(.caption)
            Text(info.label).font(.caption)
            if let p = b.path, !p.isEmpty {
                Text(p).font(.caption2).lineLimit(1).foregroundColor(.white.opacity(0.35))
            }
        }
        .foregroundColor(.white.opacity(0.42))
        .padding(.vertical, 2)
    }

    private func toolInfo(_ tool: String?) -> (icon: String, label: String) {
        switch tool ?? "" {
        case "Bash": return ("terminal", "终端")
        case "Write": return ("square.and.pencil", "写入")
        case "Edit": return ("pencil", "编辑")
        case "Read": return ("magnifyingglass", "查阅")
        case "TaskOutput": return ("tray.and.arrow.down", "输出")
        case "TodoWrite": return ("checklist", "清单")
        default:
            let t = tool ?? "工具"
            return ("wrench.and.screwdriver", t)
        }
    }
}
