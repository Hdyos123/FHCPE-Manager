import Foundation
import CommonCrypto

/// 纯原生 CPE API 客户端（不经 WebView）
/// 用于 WKWebView 网络受限时的兜底方案
final class CpeNativeAPI {
    static let shared = CpeNativeAPI()

    private var host: String = "http://192.168.8.1"
    private var user: String = "superadmin"
    private var pass: String = ""
    private var sid: String = ""
    private let iv = Data("pqrstuvwxyz{|}~".utf8)

    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        session = URLSession(configuration: cfg)
    }

    func configure(host: String, user: String, pass: String) {
        self.host = host.hasPrefix("http") ? host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                                           : "http://" + host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.user = user
        self.pass = pass
        self.sid = ""
    }

    // MARK: - 加解密

    private func cbc(_ data: Data, key: Data, encrypt: Bool) -> Data? {
        var out = Data(count: data.count + kCCBlockSizeAES128)
        var outLen = 0
        let op = CCOperation(encrypt ? kCCEncrypt : kCCDecrypt)
        let st = out.withUnsafeMutableBytes { o in
            data.withUnsafeBytes { d in
                key.withUnsafeBytes { k in
                    iv.withUnsafeBytes { i in
                        CCCrypt(op, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                k.baseAddress, key.count, i.baseAddress,
                                d.baseAddress, data.count,
                                o.baseAddress, out.count, &outLen)
                    }
                }
            }
        }
        guard st == kCCSuccess else { return nil }
        return out.prefix(outLen)
    }

    private func encrypt(_ plain: String) -> String? {
        guard sid.count >= 16, let kd = sid.prefix(16).data(using: .utf8),
              let pd = plain.data(using: .utf8),
              let enc = cbc(pd, key: kd, encrypt: true) else { return nil }
        return enc.map { String(format: "%02x", $0) }.joined()
    }

    private func decrypt(_ hex: String) -> String? {
        guard sid.count >= 16, let kd = sid.prefix(16).data(using: .utf8) else { return nil }
        var bytes = [UInt8]()
        var i = hex.startIndex
        while i < hex.endIndex {
            let n = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let b = UInt8(hex[i..<n], radix: 16) { bytes.append(b) }
            i = n
        }
        guard let dec = cbc(Data(bytes), key: kd, encrypt: false) else { return nil }
        return String(data: dec, encoding: .utf8)
    }

    // MARK: - 请求

    private func rnd() -> String {
        String(format: "%.16f", Double.random(in: 0..<1)).replacingOccurrences(of: "0.", with: "")
    }

    private func request(_ path: String, body: String? = nil) async throws -> String {
        guard let url = URL(string: host + path) else { throw NError.badURL }
        var req = URLRequest(url: url)
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue(host + "/main.html", forHTTPHeaderField: "Referer")
        if let body {
            req.httpMethod = "POST"
            req.httpBody = Data(body.utf8)
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw NError.badResponse }
        if http.statusCode == 400 { throw NError.locked }
        guard http.statusCode == 200 else { throw NError.http(http.statusCode) }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - 登录

    func login() async throws {
        // 1. sessionid
        let t = try await request("/api/tmp/FHNCAPIS?ajaxmethod=get_refresh_sessionid&_=\(rnd())")
        guard let d = t.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let s = o["sessionid"] as? String else {
            throw NError.noSession
        }
        sid = s

        // 2. 组装并加密
        let inner: [String: Any] = [
            "dataObj": ["username": user, "password": pass],
            "ajaxmethod": "DO_WEB_LOGIN",
            "sessionid": sid
        ]
        guard let pd = try? JSONSerialization.data(withJSONObject: inner),
              let ps = String(data: pd, encoding: .utf8),
              let payload = encrypt(ps) else {
            throw NError.crypto
        }

        // 3. POST 登录
        let r = try await request("/api/sign/DO_WEB_LOGIN?_\(rnd())", body: payload)
        let trimmed = r.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("0|") { return }
        if trimmed.hasPrefix("4") { throw NError.badCredentials }
        if trimmed.hasPrefix("2") || trimmed.hasPrefix("3") { throw NError.locked }
        throw NError.loginFailed(trimmed)
    }

    // MARK: - 数据

    private func decode(_ raw: String) -> [String: Any] {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return [:] }
        if t.hasPrefix("{") {
            return (try? JSONSerialization.jsonObject(with: Data(t.utf8)) as? [String: Any]) ?? [:]
        }
        guard let plain = decrypt(t),
              let d = plain.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return [:]
        }
        return o
    }

    private func refreshSession() async throws {
        let t = try await request("/api/tmp/FHNCAPIS?ajaxmethod=get_refresh_sessionid&_=\(rnd())")
        if let d = t.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let s = o["sessionid"] as? String {
            sid = s
        }
    }

    func values(_ mapping: [String: String]) async throws -> [String: String] {
        try await refreshSession()
        let inner: [String: Any] = [
            "ajaxmethod": "get_value_by_xmlnode",
            "multipost": 1,
            "dataObj": ["data_1": mapping],
            "sessionid": sid
        ]
        guard let pd = try? JSONSerialization.data(withJSONObject: inner),
              let ps = String(data: pd, encoding: .utf8),
              let payload = encrypt(ps) else { throw NError.crypto }
        let r = try await request("/api/tmp/FHAPIS?_\(rnd())", body: payload)
        let o = decode(r)
        guard let d1 = o["data_1"] as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in d1 {
            if let s = v as? String { out[k] = s }
            else if let n = v as? NSNumber { out[k] = n.stringValue }
        }
        return out
    }

    func multipost(method: String, data: [String: Any]) async throws -> [[String: Any]] {
        try await refreshSession()
        let inner: [String: Any] = [
            "ajaxmethod": method,
            "multipost": 1,
            "dataObj": data,
            "sessionid": sid
        ]
        guard let pd = try? JSONSerialization.data(withJSONObject: inner),
              let ps = String(data: pd, encoding: .utf8),
              let payload = encrypt(ps) else { throw NError.crypto }
        let r = try await request("/api/tmp/FHAPIS?_\(rnd())", body: payload)
        let o = decode(r)
        if let d1 = o["data_1"] as? [String: Any],
           let arr = d1["data"] as? [[String: Any]] {
            return arr
        }
        return []
    }

    func setSingle(url: String, value: String) async throws {
        try await refreshSession()
        let inner: [String: Any] = [
            "ajaxmethod": "set_single_by_xmlnode",
            "dataObj": ["url": url, "value": value],
            "sessionid": sid
        ]
        guard let pd = try? JSONSerialization.data(withJSONObject: inner),
              let ps = String(data: pd, encoding: .utf8),
              let payload = encrypt(ps) else { throw NError.crypto }
        _ = try await request("/api/tmp/FHAPIS?_\(rnd())", body: payload)
    }

    func runCommand(_ key: String) async throws {
        try await refreshSession()
        let inner: [String: Any] = [
            "ajaxmethod": "do_cmd_web",
            "dataObj": ["key": key],
            "sessionid": sid
        ]
        guard let pd = try? JSONSerialization.data(withJSONObject: inner),
              let ps = String(data: pd, encoding: .utf8),
              let payload = encrypt(ps) else { throw NError.crypto }
        _ = try await request("/api/tmp/FHAPIS?_\(rnd())", body: payload)
    }
}

enum NError: LocalizedError {
    case badURL, badResponse, noSession, crypto, locked
    case badCredentials
    case http(Int)
    case loginFailed(String)

    var errorDescription: String? {
        switch self {
        case .badURL:          return "地址格式不正确"
        case .badResponse:     return "设备响应异常"
        case .noSession:       return "无法获取会话，请确认连着 CPE 的 Wi-Fi"
        case .crypto:          return "加密失败"
        case .locked:          return "登录被锁定，请等 1 分钟"
        case .badCredentials:  return "用户名或密码错误"
        case .http(let c):     return "HTTP \(c)"
        case .loginFailed(let s): return "登录失败（\(s.prefix(30))）"
        }
    }
}
