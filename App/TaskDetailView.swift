import SwiftUI

// 云端模式的任务详情：经中继拉取会话消息，原生渲染。
struct TaskDetailView: View {
    @ObservedObject var mon = RelayMonitor.shared
    let task: TaskSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
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
