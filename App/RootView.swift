import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if state.configured {
                mainView
            } else {
                SetupView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            state.handleBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            state.handleForeground()
        }
    }

    @ViewBuilder private var mainView: some View {
        ZStack(alignment: .top) {
            if let url = URL(string: state.serverURL) {
                PocketWebView(url: url)
                    .ignoresSafeArea(edges: .bottom)
            }
            HStack {
                Button {
                    state.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 34, height: 30)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Capsule())
                }
                Spacer()
                Button {
                    state.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 34, height: 30)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)
        }
        .sheet(isPresented: $state.showSettings) {
            SettingsView()
        }
    }
}

// 首次启动：填电脑上 Pocket 的地址（含 token）
struct SetupView: View {
    @EnvironmentObject var state: AppState
    @State private var input = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)
            Text("连接我的电脑 Pocket").font(.title2).bold()
            Text("在电脑浏览器打开 http://localhost:18813/qr\n手机扫码，或直接粘贴电脑显示的带 token 地址")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            TextField("http://192.168.x.x:18813/?token=...", text: $input)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 28)
            if let error {
                Text(error).font(.footnote).foregroundColor(.red)
            }
            Button {
                if let err = state.save(url: input) {
                    self.error = err
                } else {
                    LocalNotify.request()
                    state.objectWillChange.send()
                }
            } label: {
                Text("保存并连接")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 28)
            Spacer()
        }
        .padding()
    }
}

// 设置页：改地址、官方中继配对、重置
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var relayMon = RelayMonitor.shared
    @Environment(\.dismiss) private var dismiss
    @State private var input = AppSettings.serverURL
    @State private var officialInput = RelayMonitor.shared.officialURL
    @State private var msg = ""

    var body: some View {
        NavigationView {
            Form {
                Section("服务器地址（Pocket 派任务/历史）") {
                    TextField("http://...", text: $input)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("保存地址") {
                        if let err = state.save(url: input) {
                            msg = err
                        } else {
                            msg = "已保存，正在重连…"
                            state.reload()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismiss() }
                        }
                    }
                    if !msg.isEmpty {
                        Text(msg).font(.footnote).foregroundColor(.secondary)
                    }
                }
                Section("官方远控链接（任意网络的后台通知）") {
                    TextField("https://zcode.z.ai/remote/v4?sid=...", text: $officialInput)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("保存并连接") {
                        relayMon.connect(from: officialInput)
                    }
                    if relayMon.hasLink {
                        HStack(spacing: 6) {
                            Circle().fill(relayMon.stateLabel == "已连接" ? Color.green : Color.orange).frame(width: 8, height: 8)
                            Text("中继状态：\(relayMon.stateLabel)（退后台自动接管）")
                                .font(.footnote).foregroundColor(.secondary)
                        }
                        Button("清除配对", role: .destructive) {
                            officialInput = ""
                            relayMon.disconnectAll()
                        }
                    }
                    Text("在电脑 ZCode 开「远程控制」，复制链接粘到这里。保存后 App 退到后台会自动通过 ZCode 官方云接收任务通知，任何网络可用。")
                        .font(.footnote).foregroundColor(.secondary)
                }
                Section("后台通知") {
                    Text("退到后台后：Pocket 地址可达时轮询本机任务（20 秒）；官方远控配对后走 ZCode 云中继收桌面任务。完成/出错弹系统横幅，点通知直达会话。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Section {
                    Button("清除全部配置", role: .destructive) {
                        AppSettings.serverURL = ""
                        state.serverURL = ""
                        relayMon.disconnectAll()
                        state.objectWillChange.send()
                        dismiss()
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
