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
    /// AES-CBC 初始向量：ASCII 0x70...0x7F（共 16 字节）
    /// 注意末尾是 0x7F (DEL)，不可见字符，不能用字符串字面量
    /// 等价于 Python 的 bytes(range(112, 128))
    private let iv = Data((112...127).map { UInt8($0) })

    /// 诊断：记录每一步原始响应
    static var trace: [String] = []
    static func log(_ s: String) {
        trace.append(s)
        if trace.count > 20 { trace.removeFirst() }
    }

    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 25
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

    /// AES-128-CBC + PKCS7，与设备前端完全一致
    /// key = sessionid 前 16 字节，iv = "pqrstuvwxyz{|}~"
    private func cbc(_ data: Data, key: Data, encrypt op: Bool) -> Data? {
        guard key.count == 16 else {
            Self.log("cbc: key length != 16 (\(key.count))")
            return nil
        }
        let inBytes = Array(data)
        let keyBytes = Array(key)
        let ivBytes = Array(iv)
        guard ivBytes.count == 16 else {
            Self.log("cbc: iv length != 16")
            return nil
        }

        let bufSize = inBytes.count + kCCBlockSizeAES128
        var out = [UInt8](repeating: 0, count: bufSize)
        var moved = 0

        let status = out.withUnsafeMutableBufferPointer { outBuf -> CCCryptorStatus in
            inBytes.withUnsafeBufferPointer { inBuf -> CCCryptorStatus in
                keyBytes.withUnsafeBufferPointer { keyBuf -> CCCryptorStatus in
                    ivBytes.withUnsafeBufferPointer { ivBuf -> CCCryptorStatus in
                        CCCrypt(CCOperation(op ? kCCEncrypt : kCCDecrypt),
                                CCAlgorithm(kCCAlgorithmAES128),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyBuf.baseAddress, keyBytes.count,
                                ivBuf.baseAddress,
                                inBuf.baseAddress, inBytes.count,
                                outBuf.baseAddress, bufSize,
                                &moved)
                    }
                }
            }
        }

        if status != kCCSuccess {
            Self.log("cbc: CCCrypt status=\(status), in=\(inBytes.count), out=\(bufSize)")
            return nil
        }
        return Data(out[0..<moved])
    }

    private func encrypt(_ plain: String) -> String? {
        guard sid.count >= 16 else {
            Self.log("encrypt: sid too short (\(sid.count))")
            return nil
        }
        guard let kd = String(sid.prefix(16)).data(using: .utf8), kd.count == 16 else {
            Self.log("encrypt: key derive failed")
            return nil
        }
        guard let pd = plain.data(using: .utf8) else {
            Self.log("encrypt: utf8 encode failed")
            return nil
        }
        guard let enc = cbc(pd, key: kd, encrypt: true) else { return nil }
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

    // MARK: - 自检

    /// 用已知测试向量验证加密实现
    /// 明文/密文由 Python 版（已验证可用）生成
    func selfTest() -> (ok: Bool, detail: String) {
        let savedSid = sid
        sid = "abcdefghijklmnop1234567890abcdef"
        let plain = #"{"dataObj":{"username":"admin","password":"test"},"ajaxmethod":"DO_WEB_LOGIN","sessionid":"abcdefghijklmnop1234567890abcdef"}"#
        let expect = "e14bf4917f7fea1e6eae03934f104fbe6b3cb2fa5b4bc4c13b50eb4f2eaaa90e"
            + "165b4795a8d73e09bd4866c28da3c40deec597029e8186741ec80001a05fdd0c"
            + "96e1a3b9ef5f09216447c749dbef163fe5a9f713915ad6b83bdf16a0fa510bb9"
            + "d0286d8b56b95ac468c18fd00bbf3c523c9705811eaab5632f3d2e027a7637f5"
        let got = encrypt(plain) ?? "<nil>"
        sid = savedSid
        let ok = got.lowercased() == expect.lowercased()
        return (ok, ok ? "加密自检通过" : "加密自检失败\n期望: \(expect.prefix(32))…\n实际: \(got.prefix(32))…")
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
        if http.statusCode == 400 {
            Self.log("HTTP 400 for " + path)
            throw NError.crypto   // 400 多为加密/payload 问题，不是锁定
        }
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
        Self.log("login raw: " + String(r.prefix(80)))
        Self.log("payload len: \(payload.count), escaped: \(payload.allSatisfy { $0.isHexDigit })")
        switch LoginCode.parse(r) {
        case .ok:               return
        case .badCredentials:   throw NError.badCredentials
        case .busy:             throw NError.busy
        case .sessionExpired:   throw NError.sessionExpired
        case .unknown(let s):   throw NError.loginFailed(s)
        }
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
    case busy, sessionExpired

    var errorDescription: String? {
        switch self {
        case .badURL:          return "地址格式不正确"
        case .badResponse:     return "设备响应异常"
        case .noSession:       return "无法获取会话，请确认连着 CPE 的 Wi-Fi"
        case .crypto:          return "加密失败"
        case .locked:          return "登录被锁定，请等 1 分钟"
        case .badCredentials:  return "用户名或密码错误"
        case .http(let c):     return "HTTP \(c)"
        case .loginFailed(let s): return "登录失败（" + String(s.prefix(30)) + "）"
        case .busy:            return "设备繁忙，请稍后重试"
        case .sessionExpired:  return "会话已过期，请重试"
        }
    }
}
