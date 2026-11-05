import Foundation
import CryptoKit

struct OfficialLink: Equatable {
    var origin: String
    var remotePath: String
    var deviceSid: String
    /// 旧版（桌面 <3.16）HMAC 挑战凭据；新版账号令牌配对为空串
    var passHash: String
    var timestamp: Int
    var deviceMid: String?
    var deviceName: String?
    var appVersion: String?
    var theme: String?
    /// 新版桌面（≥3.16）：二维码只带 sid/mid，无 hash/t，配对走账号 JWT 换短时令牌
    var isV2: Bool

    /// v4: wss://<origin>/ws?mid=...；v2: wss://zcode.z.ai/api/v1/remote/ws2?mid=...
    /// v2 的 token 由连接前实时获取（60 秒有效），不放在保存的链接里。
    var relayWebSocketURL: URL? {
        guard let url = URL(string: origin) else { return nil }
        var ws = URLComponents()
        if isV2 {
            ws.scheme = "wss"
            ws.host = url.host
            ws.port = url.port
            ws.path = "/api/v1/remote/ws2"
        } else {
            ws.scheme = (url.scheme == "http") ? "ws" : "wss"
            ws.host = url.host
            ws.port = url.port
            ws.path = "/ws"
        }
        if let deviceMid, !deviceMid.isEmpty {
            ws.queryItems = [URLQueryItem(name: "mid", value: deviceMid)]
        }
        return ws.url
    }

    var displayName: String {
        if let deviceName, !deviceName.isEmpty { return deviceName }
        return URL(string: origin)?.host ?? "ZCode"
    }
}

enum OfficialLinkParser {
    static func parse(_ raw: String) -> OfficialLink? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let items = comps.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let sid = value("sid"), !sid.isEmpty else { return nil }
        let hash = value("hash")
        // 新版桌面（≥3.16.x）二维码没有 hash/t，只有 sid/mid/name/app_version
        let isV2 = (hash ?? "").isEmpty
        var origin = "https://zcode.z.ai"
        if let scheme = comps.scheme, let host = comps.host {
            origin = "\(scheme)://\(host)"
            if let port = comps.port { origin += ":\(port)" }
        }
        let path = comps.path.isEmpty ? "/remote/v4" : comps.path
        var timestamp = 0
        if !isV2 {
            // 旧版必须带 hash + t（HMAC 挑战）
            guard let hash, !hash.isEmpty,
                  let t = value("t"), let parsed = Int(t) else { return nil }
            timestamp = parsed
        } else if (value("mid") ?? "").isEmpty {
            // 新版必须带 mid：终端 ws 握手不带 mid 会永远停在 waiting，无法配对
            return nil
        }
        return OfficialLink(
            origin: origin,
            remotePath: path,
            deviceSid: sid,
            passHash: hash ?? "",
            timestamp: timestamp,
            deviceMid: value("mid"),
            deviceName: value("name"),
            appVersion: value("app_version"),
            theme: value("theme"),
            isV2: isV2
        )
    }
}

enum OfficialProof {
    static func hmacBase64URL(passHash: String, nonce: String, role: String, deviceSid: String) -> String {
        let message = "\(nonce)|\(role)|\(deviceSid)"
        let key = SymmetricKey(data: Data(passHash.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(mac).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
