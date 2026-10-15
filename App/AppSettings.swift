import Foundation

// 服务器地址持久化：形如 http://192.168.1.114:18813/?token=xxxx 或隧道 https 地址
enum AppSettings {
    static let key = "pocket.serverURL"

    static var serverURL: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var token: String {
        guard let comps = URLComponents(string: serverURL) else { return "" }
        return comps.queryItems?.first(where: { $0.name == "token" })?.value ?? ""
    }

    static var isValid: Bool {
        guard let url = URL(string: serverURL), let host = url.host, !host.isEmpty else { return false }
        return serverURL.lowercased().hasPrefix("http://") || serverURL.lowercased().hasPrefix("https://")
    }

    /// 所有任务接口的完整地址
    static var tasksAPI: String {
        guard var comps = URLComponents(string: serverURL) else { return "" }
        comps.path = "/api/all_tasks"
        comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: "token", value: token)]
        return comps.string ?? ""
    }
}
