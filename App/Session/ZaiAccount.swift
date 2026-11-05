import Foundation
import Security

// 桌面版 ≥3.16 的账号令牌配对：手机用与电脑相同的 z.ai / BigModel 账号完成
// OAuth 设备码登录换账号 JWT，连接前在线换取 60 秒短时终端令牌（不落盘）。
// JWT 存钥匙串。接口链路与桌面端 /api/v1/oauth/cli/* 完全一致。
final class ZaiAccount: ObservableObject {
    static let shared = ZaiAccount()

    static let baseURL = URL(string: "https://zcode.z.ai")!
    private let keychainService = "zcode.pocket.app.account"
    private let keychainAccount = "zcode-jwt"

    enum LoginPhase: Equatable {
        case idle
        case awaiting
        case failed(String)
        case done
    }

    @Published private(set) var loginPhase: LoginPhase = .idle
    @Published private(set) var jwt: String?
    /// 登录成功后展示用：邮箱优先，其次昵称
    @Published private(set) var userLabel: String?
    /// 本次登录使用的方式（bigmodel / zai），仅作展示
    @Published private(set) var lastProvider: String?
    /// 当前授权页地址，UI 可重新打开浏览器
    @Published private(set) var authorizeURL: URL?

    private var pollTask: Task<Void, Never>?

    private init() {
        jwt = loadJWT()
        if jwt != nil { loginPhase = .done }
    }

    var isLoggedIn: Bool { jwt != nil }

    func logout() {
        pollTask?.cancel()
        pollTask = nil
        clearJWT()
        jwt = nil
        userLabel = nil
        authorizeURL = nil
        loginPhase = .idle
    }

    /// 取消进行中的登录流程：不清除已保存的 JWT
    func cancelLogin() {
        pollTask?.cancel()
        pollTask = nil
        authorizeURL = nil
        loginPhase = jwt != nil ? .done : .idle
    }

    /// 发起浏览器授权并后台轮询直到 ready / failed。
    func startLogin(provider: String) {
        pollTask?.cancel()
        loginPhase = .awaiting
        authorizeURL = nil
        pollTask = Task { [weak self] in
            guard let self else { return }
            do {
                let flow = try await beginLogin(provider: provider)
                await MainActor.run {
                    self.lastProvider = provider
                    self.authorizeURL = flow.authorizeURL
                }
                let deadline = Date().addingTimeInterval(max(60, flow.expiresAt.timeIntervalSinceNow))
                while Date() < deadline {
                    try await Task.sleep(for: .seconds(max(2, flow.pollInterval)))
                    guard !Task.isCancelled else { return }
                    let poll = try await pollLogin(flow)
                    switch poll.status {
                    case .ready:
                        await MainActor.run {
                            self.jwt = poll.jwt
                            self.userLabel = poll.userLabel
                            self.loginPhase = .done
                        }
                        return
                    case .failed:
                        await MainActor.run { self.loginPhase = .failed("授权未完成") }
                        return
                    case .pending:
                        continue
                    }
                }
                await MainActor.run {
                    if self.loginPhase == .awaiting { self.loginPhase = .failed("授权超时") }
                }
            } catch {
                await MainActor.run { self.loginPhase = .failed(error.localizedDescription) }
            }
        }
    }

    // MARK: - 钥匙串

    private func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: keychainAccount]
    }

    private func loadJWT() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveJWT(_ value: String) {
        guard !value.isEmpty else { return }
        var query = baseQuery()
        let update: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            query[kSecValueData as String] = Data(value.utf8)
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private func clearJWT() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    // MARK: - OAuth 设备码登录

    struct LoginFlow {
        let flowID: String
        let authorizeURL: URL
        let proof: String
        let expiresAt: Date
        let pollInterval: TimeInterval
    }

    enum PollStatus { case pending, ready, failed }

    private func beginLogin(provider: String) async throws -> LoginFlow {
        let proof = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/v1/oauth/cli/init"), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(proof)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["provider": provider])
        let object = try await fetchJSON(request)
        guard object["code"] as? Int == 0, let data = object["data"] as? [String: Any],
              let flowID = data["flow_id"] as? String, flowID.count <= 256,
              let authorize = data["authorize_url"] as? String,
              let authorizeURL = URL(string: authorize), authorizeURL.scheme == "https",
              let expiresAt = data["expires_at"] as? Double, expiresAt > 0,
              let interval = data["poll_interval_sec"] as? Double, interval >= 1
        else {
            throw RelayError("无法发起账号登录，请稍后重试。")
        }
        return LoginFlow(flowID: flowID, authorizeURL: authorizeURL, proof: proof,
                         expiresAt: Date(timeIntervalSince1970: expiresAt),
                         pollInterval: max(2, interval))
    }

    private func pollLogin(_ flow: LoginFlow) async throws -> (status: PollStatus, jwt: String?, userLabel: String?) {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/v1/oauth/cli/poll/\(flow.flowID)"), timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("Bearer \(flow.proof ?? "")", forHTTPHeaderField: "Authorization")
        let object = try await fetchJSON(request)
        guard object["code"] as? Int == 0, let data = object["data"] as? [String: Any] else {
            throw RelayError("账号登录查询失败，请重试。")
        }
        let status = data["status"] as? String ?? "pending"
        if status == "ready" {
            let token = data["token"] as? String ?? ""
            guard !token.isEmpty, token.utf8.count <= 8192 else {
                throw RelayError("登录响应无效，请重试。")
            }
            saveJWT(token)
            let user = data["user"] as? [String: Any]
            let label = (user?["email"] as? String) ?? (user?["name"] as? String)
            return (.ready, token, label)
        }
        if status == "failed" { return (.failed, nil, nil) }
        return (.pending, nil, nil)
    }

    // MARK: - 终端令牌（60 秒有效，连接前现取）

    func terminalToken() async throws -> String {
        guard let jwt = jwt ?? loadJWT() else {
            throw RelayError("此链接来自新版桌面端（≥3.16），需要先在设置里登录与电脑相同的 z.ai / BigModel 账号。")
        }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/v1/remote/token"), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["role": "terminal"])
        let object = try await fetchJSON(request)
        guard object["code"] as? Int == 0, let data = object["data"] as? [String: Any],
              let token = data["token"] as? String, !token.isEmpty else {
            throw RelayError("无法获取连接令牌，请到设置里重新登录账号。")
        }
        return token
    }

    private func fetchJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RelayError("接口请求失败（HTTP \(http.statusCode)）\(body.isEmpty ? "" : "：\(body.prefix(120))")")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RelayError("接口响应格式无效。")
        }
        return object
    }
}

/// 轻量错误类型：LocalizedName 直接展示给用户
struct RelayError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
