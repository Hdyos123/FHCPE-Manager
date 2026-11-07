import Foundation
import CryptoKit

/// 华为 CPE（H153 / H155 等）原生 API 客户端
///
/// 协议要点：
/// 1. GET  /api/webserver/SesTokInfo  → 拿 SessionID Cookie + CSRF Token
/// 2. POST /api/user/login            → 密码 SHA256 → Base64，password_type=4
/// 3. 之后所有请求带 __RequestVerificationToken 头
///
/// 注意：部分固件（如 H153-381）登录后 State 仍为 -1，
/// 信号/小区类接口会被拒绝，只能用基础监控接口。
final class HuaweiAPI {
    static let shared = HuaweiAPI()

    private var host = "http://192.168.8.1"
    private var user = "admin"
    private var pass = ""
    private var token = ""
    private var cookies: [String: String] = [:]
    /// 诊断日志
    private(set) var trace: [String] = []
    private func log(_ s: String) {
        trace.append(s)
        if trace.count > 40 { trace.removeFirst() }
    }

    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        cfg.waitsForConnectivity = false
        cfg.httpShouldSetCookies = false   // 手动管理 Cookie
        session = URLSession(configuration: cfg)
    }

    func configure(host: String, user: String, pass: String) {
        self.host = host.hasPrefix("http") ? host : "http://" + host
        self.user = user
        self.pass = pass
        self.token = ""
        self.cookies = [:]
        self.trace = []
    }

    // MARK: - 底层

    private func rnd() -> String {
        String(Int(Date().timeIntervalSince1970 * 1000))
    }

    private func request(_ path: String,
                         method: String = "GET",
                         body: String? = nil) async throws -> String {
        let sep = path.contains("?") ? "&" : "?"
        guard let url = URL(string: host + path + "\(sep)_=\(rnd())") else {
            throw HError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
                     + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
                     + "Version/18.0 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("http://192.168.8.1/", forHTTPHeaderField: "Referer")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        if !token.isEmpty {
            req.setValue(token, forHTTPHeaderField: "__RequestVerificationToken")
        }
        if !cookies.isEmpty {
            req.setValue(cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; "),
                         forHTTPHeaderField: "Cookie")
        }
        if let body {
            req.httpBody = Data(body.utf8)
            req.setValue("application/xml; charset=UTF-8",
                         forHTTPHeaderField: "Content-Type")
        }

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            log("✗ 请求失败 \(path): \(error.localizedDescription)")
            throw error
        }
        guard let http = resp as? HTTPURLResponse else { throw HError.badResponse }
        log("GET \(path) -> \(http.statusCode)")

        // 抓 Set-Cookie（allHeaderFields 可能大小写不一，遍历所有头）
        for (k, v) in http.allHeaderFields {
            let key = String(describing: k).lowercased()
            guard key == "set-cookie" else { continue }
            let raw = String(describing: v)
            // 可能有多条，用逗号分隔，但 Expires 里也有逗号，需小心
            for chunk in raw.components(separatedBy: ",SessionID=") {
                let seg = chunk.hasPrefix("SessionID=") ? chunk : "SessionID=" + chunk
                let first = seg.components(separatedBy: ";").first ?? ""
                guard let eq = first.firstIndex(of: "=") else { continue }
                let name = String(first[first.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
                let value = String(first[first.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty && !value.isEmpty {
                    cookies[name] = value
                }
            }
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        return text
    }

    /// 刷新 CSRF token
    private func refreshToken() async throws {
        let txt = try await request("/api/webserver/SesTokInfo")
        if let t = xmlValue(txt, tag: "TokInfo") {
            token = t.replacingOccurrences(of: "&amp;", with: "&")
            log("token 获取成功 (\(token.count) 字符)")
        } else {
            log("✗ token 解析失败: \(txt.prefix(80))")
        }
        log("Cookie: \(cookies.keys.joined(separator: ","))")
    }

    // MARK: - 登录

    func login() async throws {
        trace.removeAll()
        log("开始登录 \(host)")
        try await refreshToken()

        // 密码：SHA256 → Base64
        let digest = SHA256.hash(data: Data(pass.utf8))
        let enc = Data(digest).base64EncodedString()

        let xml = "<request><username>\(xmlEscape(user))</username>"
                + "<password>\(enc)</password>"
                + "<password_type>4</password_type></request>"

        let r = try await request("/api/user/login", method: "POST", body: xml)
        let compact = r.replacingOccurrences(of: " ", with: "")
                         .replacingOccurrences(of: "\n", with: "")
                         .replacingOccurrences(of: "\r", with: "")
                         .replacingOccurrences(of: "\t", with: "")
        if compact.contains("<response>OK</response>") {
            log("✓ 登录返回 OK")
            try await refreshToken()
            return
        }
        log("✗ 登录返回: \(r.prefix(80))")
        if r.contains("<code>108006</code>") {
            throw HError.locked
        }
        if r.contains("<code>108001</code>") || r.contains("<code>108003</code>") {
            throw HError.badCredentials
        }
        throw HError.loginFailed(r)
    }

    // MARK: - 数据

    /// 监控状态
    func status() async throws -> [String: String] {
        let t = try await request("/api/monitoring/status")
        return xmlToDict(t)
    }

    /// 实时/累计流量
    func traffic() async throws -> [String: String] {
        let t = try await request("/api/monitoring/traffic-statistics")
        return xmlToDict(t)
    }

    /// 本月流量
    func monthTraffic() async throws -> [String: String] {
        let t = try await request("/api/monitoring/month_statistics")
        return xmlToDict(t)
    }

    /// 运营商
    func plmn() async throws -> [String: String] {
        let t = try await request("/api/net/current-plmn")
        return xmlToDict(t)
    }

    /// 设备信息
    func deviceInfo() async throws -> [String: String] {
        let t = try await request("/api/device/basic_information")
        return xmlToDict(t)
    }

    /// 移动数据开关状态
    func dataSwitch() async throws -> Bool {
        let t = try await request("/api/dialup/mobile-dataswitch")
        return xmlValue(t, tag: "dataswitch") == "1"
    }

    /// 切换移动数据
    func setDataSwitch(_ on: Bool) async throws {
        let xml = "<request><dataswitch>\(on ? 1 : 0)</dataswitch></request>"
        _ = try await request("/api/dialup/mobile-dataswitch", method: "POST", body: xml)
    }

    /// 重启
    func reboot() async throws {
        _ = try await request("/api/device/control",
                              method: "POST",
                              body: "<request><Control>1</Control></request>")
    }

    // MARK: - XML 工具

    private func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    func xmlValue(_ xml: String, tag: String) -> String? {
        guard let s = xml.range(of: "<\(tag)>"),
              let e = xml.range(of: "</\(tag)>") else { return nil }
        let v = xml[s.upperBound..<e.lowerBound]
        return v.isEmpty ? nil : String(v)
    }

    func xmlToDict(_ xml: String) -> [String: String] {
        var out: [String: String] = [:]
        var idx = xml.startIndex
        while let open = xml.range(of: "<", range: idx..<xml.endIndex) {
            let nameEnd = xml[open.upperBound...].firstIndex(of: ">") ?? xml.endIndex
            let name = String(xml[open.upperBound..<nameEnd])
            guard !name.hasPrefix("/"), !name.hasPrefix("?"),
                  !name.hasSuffix("/") else {
                idx = xml.index(after: nameEnd)
                continue
            }
            guard let close = xml.range(of: "</\(name)>", range: nameEnd..<xml.endIndex) else {
                idx = xml.index(after: nameEnd)
                continue
            }
            let value = String(xml[xml.index(after: nameEnd)..<close.lowerBound])
            if !value.contains("<") {
                out[name] = value
            }
            idx = close.upperBound
        }
        return out
    }
}

enum HError: LocalizedError {
    case badURL, badResponse, locked, badCredentials
    case loginFailed(String)

    var errorDescription: String? {
        switch self {
        case .badURL:          return "地址格式不正确"
        case .badResponse:     return "设备响应异常"
        case .locked:          return "账号已锁定，请等待 1 分钟后重试"
        case .badCredentials:  return "账号或密码不正确"
        case .loginFailed(let s): return "登录失败"
        }
    }
}
