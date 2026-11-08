import Foundation

/// 会话持久化
///
/// 目标：App 重新打开时先用上次的会话探测，成功就免登录。
/// 三家设备的凭证形式不同：
/// - 烽火：sessionid（32 字符）
/// - 华为：SessionID cookie
/// - OPPO：WKWebView 的 cookie（由 websiteDataStore 自己管）
enum SessionStore {

    private static let keyPrefix = "cpe.session."

    struct Payload: Codable {
        var token: String        // 烽火 sessionid / 华为 cookie
        var host: String
        var savedAt: Date
    }

    /// 保存会话
    static func save(_ token: String, host: String, vendor: String) {
        guard !token.isEmpty else { return }
        let p = Payload(token: token, host: host, savedAt: Date())
        if let d = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(d, forKey: keyPrefix + vendor)
        }
    }

    /// 读取会话（可选最大有效期）
    static func load(vendor: String, host: String, maxAge: TimeInterval? = nil) -> String? {
        guard let d = UserDefaults.standard.data(forKey: keyPrefix + vendor),
              let p = try? JSONDecoder().decode(Payload.self, from: d) else { return nil }
        // 主机变了就作废
        guard p.host == host else { return nil }
        if let age = maxAge, Date().timeIntervalSince(p.savedAt) > age {
            return nil
        }
        return p.token
    }

    /// 清除
    static func clear(vendor: String) {
        UserDefaults.standard.removeObject(forKey: keyPrefix + vendor)
    }

    /// 全部清除
    static func clearAll() {
        for v in ["fiberhome", "oppo", "huawei"] {
            clear(vendor: v)
        }
    }
}
