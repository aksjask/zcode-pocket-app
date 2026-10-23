import SwiftUI

// 云端模式的任务会话页：经中继拉取会话消息，官方深色风格渲染（含 markdown）+ 底部 composer 续聊。
struct TaskDetailView: View {
    @ObservedObject var mon = RelayMonitor.shared
    let task: TaskSummary
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var sending = false
    @State private var refreshTimer: Timer?

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
                                            messageView(m)
                                                .id(m.id)
                                        }
                                    }
                                    .padding()
                                }
                                .onChange(of: mon.messages) { _ in
                                    scrollToBottom(proxy, msgs: msgs)
                                }
                                .onAppear {
                                    scrollToBottom(proxy, msgs: msgs)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        scrollToBottom(proxy, msgs: msgs)
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        scrollToBottom(proxy, msgs: msgs)
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
            // 详情页打开期间持续自动拉新（桌面回复实时进来）
            refreshTimer?.invalidate()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak mon] _ in
                mon?.loadMessages(task.id)
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func lastId(_ msgs: [ChatMessage]) -> String {
        msgs.last?.blocks.last?.id ?? msgs.last?.id ?? "top"
    }

    /// 稳妥滚底：立即 + 延迟双保险（等内容完成布局）
    private func scrollToBottom(_ proxy: ScrollViewProxy, msgs: [ChatMessage]) {
        let id = lastId(msgs)
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }

    // ---------- 消息渲染 ----------

    @ViewBuilder private func messageView(_ m: ChatMessage) -> some View {
        let blocks = m.blocks.filter { b in
            !(b.kind == "text" && b.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if m.isUser {
            ForEach(blocks) { b in
                HStack(alignment: .top) {
                    Spacer(minLength: 52)
                    Text(b.text)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color(red: 0.16, green: 0.19, blue: 0.27))
                        .cornerRadius(12)
                }
            }
        } else {
            ForEach(blocks) { b in
                switch b.kind {
                case "text":
                    assistantBody(b.text)
                case "tool":
                    toolRow(b)
                default:
                    EmptyView()
                }
            }
        }
    }

    private func toolRow(_ b: ChatBlock) -> some View {
        let info = toolInfo(b.tool)
        return HStack(spacing: 6) {
            Image(systemName: info.icon).font(.caption)
            Text(info.label).font(.caption)
            if !b.text.isEmpty {
                Text(b.text).font(.caption).lineLimit(1).foregroundColor(.white.opacity(0.3))
            } else if let p = b.path, !p.isEmpty {
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
        case "Glob": return ("folder", "找文件")
        case "Grep": return ("text.magnifyingglass", "搜索")
        default:
            let t = tool ?? "工具"
            return ("wrench.and.screwdriver", t)
        }
    }

    // ---------- 轻量 markdown 渲染 ----------

    private enum MRow {
        case header(String, Int)   // 文本, 级别
        case text(String)          // 普通段（内联 markdown）
        case bullet(String)        // 无序列表项
        case numbered(String, String) // 序号, 内容
        case code(String)          // 代码块
        case table([String])       // 表格行
        case blank
    }

    private func parseRows(_ text: String) -> [MRow] {
        var rows: [MRow] = []
        var inCode = false
        var codeBuf: [String] = []
        var paraBuf: [String] = []
        var tableBuf: [String] = []

        func flushPara() {
            guard !paraBuf.isEmpty else { return }
            rows.append(.text(paraBuf.joined(separator: "\n")))
            paraBuf = []
        }
        func flushTable() {
            guard !tableBuf.isEmpty else { return }
            rows.append(.table(tableBuf))
            tableBuf = []
        }
        func flushCode() {
            guard !codeBuf.isEmpty else { return }
            rows.append(.code(codeBuf.joined(separator: "\n")))
            codeBuf = []
        }

        for raw in text.components(separatedBy: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                flushPara(); flushTable()
                if inCode { flushCode(); inCode = false } else { inCode = true }
                continue
            }
            if inCode { codeBuf.append(raw); continue }
            if t.hasPrefix("|") {
                flushPara()
                // 跳过分隔行 |---|---|
                if t.range(of: #"^\|[\s\-:|]+\|?$"#, options: .regularExpression) != nil { continue }
                let cells = t.dropFirst().dropLast().components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                tableBuf.append(cells.joined(separator: "   "))
                continue
            }
            flushTable()
            if t.isEmpty {
                flushPara()
                rows.append(.blank)
                continue
            }
            if t.hasPrefix("####") { flushPara(); rows.append(.header(String(t.dropFirst(4)).trimmingCharacters(in: .whitespaces), 4)); continue }
            if t.hasPrefix("###") { flushPara(); rows.append(.header(String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces), 3)); continue }
            if t.hasPrefix("##") { flushPara(); rows.append(.header(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces), 2)); continue }
            if t.hasPrefix("#") { flushPara(); rows.append(.header(String(t.dropFirst()).trimmingCharacters(in: .whitespaces), 1)); continue }
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("• ") {
                flushPara()
                rows.append(.bullet(String(t.dropFirst(2))))
                continue
            }
            if let r = t.range(of: #"^\d{1,2}[\.、] "#, options: .regularExpression) {
                flushPara()
                rows.append(.numbered(String(t[...r.upperBound]).trimmingCharacters(in: .whitespaces), String(t[r.upperBound...])))
                continue
            }
            paraBuf.append(t)
        }
        flushPara(); flushTable(); flushCode()
        return rows
    }

    @ViewBuilder private func rowView(_ row: MRow) -> some View {
        switch row {
        case .header(let text, let level):
            inlineText(text)
                .font(.system(size: level <= 1 ? 19 : level == 2 ? 17 : 15.5, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 4)
        case .text(let text):
            inlineText(text)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 7) {
                Text("•").foregroundColor(.white.opacity(0.65)).font(.subheadline)
                inlineText(text).font(.system(size: 15.5))
            }
        case .numbered(let num, let text):
            HStack(alignment: .top, spacing: 7) {
                Text(num).foregroundColor(.white.opacity(0.65)).font(.subheadline)
                inlineText(text).font(.system(size: 15.5))
            }
        case .code(let code):
            Text(code)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundColor(Color(white: 0.85))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.08, green: 0.08, blue: 0.1))
                .cornerRadius(10)
        case .table(let cells):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                    inlineText(c).font(.system(size: 13, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.08, green: 0.08, blue: 0.1))
            .cornerRadius(10)
        case .blank:
            Spacer().frame(height: 4)
        }
    }

    /// 单行内联 markdown（**加粗** `代码` [链接]）走系统 AttributedString 解析
    @ViewBuilder private func inlineText(_ s: String) -> some View {
        let nonEmpty = s.isEmpty ? " " : s
        if let attr = try? AttributedString(
            markdown: nonEmpty,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attr)
                .font(.system(size: 15.5))
                .foregroundColor(Color(white: 0.92))
                .lineSpacing(4)
        } else {
            Text(nonEmpty)
                .font(.system(size: 15.5))
                .foregroundColor(Color(white: 0.92))
                .lineSpacing(4)
        }
    }

    private func assistantBody(_ text: String) -> some View {
        let rows = parseRows(text)
        return VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                rowView(row)
            }
        }
    }

    // ---------- 底部 composer（官方风格） ----------

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
}
