import Foundation
import CryptoKit
import Security

// MARK: - 极简 XML

/// 轻量 XML 节点（华为接口全是 XML）
final class XMLNode {
    let name: String
    var value: String = ""
    var children: [XMLNode] = []

    init(name: String) { self.name = name }

    func child(_ n: String) -> XMLNode? {
        children.first { $0.name == n }
    }

    /// 取子节点文本
    func text(_ n: String) -> String? {
        guard let c = child(n) else { return nil }
        let t = c.value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 取所有同名子节点
    func all(_ n: String) -> [XMLNode] {
        children.filter { $0.name == n }
    }

    /// 递归找第一个同名节点
    func find(_ n: String) -> XMLNode? {
        if name == n { return self }
        for c in children {
            if let r = c.find(n) { return r }
        }
        return nil
    }
}

private final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    var root: XMLNode?
    private var stack: [XMLNode] = []

    func parser(_ p: XMLParser, didStartElement e: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        let node = XMLNode(name: e)
        if let last = stack.last { last.children.append(node) } else { root = node }
        stack.append(node)
    }

    func parser(_ p: XMLParser, foundCharacters s: String) {
        stack.last?.value += s
    }

    func parser(_ p: XMLParser, didEndElement e: String,
                namespaceURI: String?, qualifiedName: String?) {
        if !stack.isEmpty { stack.removeLast() }
    }
}

// MARK: - 华为错误

enum HuaweiError: LocalizedError {
    case badHost
    case http(Int)
    case device(code: String, message: String)
    case noSession
    case loginFailed(String)
    case parse

    var errorDescription: String? {
        switch self {
        case .badHost:              return "地址无效"
        case .http(let c):          return "设备返回 HTTP \(c)"
        case .device(let c, let m): return "设备返回错误 \(c)：\(m)"
        case .noSession:            return "拿不到设备会话，请重启设备后重试"
        case .loginFailed(let m):   return "登录失败：\(m)"
        case .parse:                return "设备返回的内容无法解析"
        }
    }
}

// MARK: - 华为 HiLink 客户端

final class HuaweiAPI {
    static let shared = HuaweiAPI()
    private init() {}

    private(set) var host: String = ""
    private(set) var loggedIn = false
    private(set) var lastErrorText: String = ""

    private var sessionCookie: String = ""
    private var token: String = ""
    private var session: URLSession!
    private var user: String = "admin"

    /// 最近一次登录用的凭据（用于自动重登）
    private var password: String = ""

    // MARK: 配置

    func configure(host: String) {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard h != self.host || session == nil else { return }
        self.host = h
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 25
        cfg.httpShouldSetCookies = false     // 手动管理 Cookie
        cfg.httpCookieAcceptPolicy = .never
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: cfg)
        loggedIn = false
        sessionCookie = ""
        token = ""
    }

    // MARK: 登录（SCRAM-SHA256）

    func login(host: String, user: String, password: String) async throws {
        configure(host: host)
        self.user = user
        self.password = password
        loggedIn = false
        lastErrorText = ""

        // ① 会话与令牌
        let ses = try await rawRequest("GET", "/api/webserver/SesTokInfo", body: nil)
        if let s = ses.text("SesInfo") {
            sessionCookie = s
        } else {
            throw HuaweiError.noSession
        }
        token = ses.text("TokInfo") ?? ""

        // ② challenge
        let firstNonce = Self.randomNonce()
        let challengeBody = "<request><username>\(user)</username><firstnonce>\(firstNonce)</firstnonce><mode>1</mode></request>"
        let chal = try await rawRequest("POST", "/api/user/challenge_login", body: challengeBody)

        guard let saltB64 = chal.text("salt"),
              let iterStr = chal.text("iterations"),
              let serverNonce = chal.text("servernonce"),
              let iterations = Int(iterStr) else {
            // 固件可能不支持 SCRAM，退回旧式登录
            try await legacyLogin(user: user, password: password)
            return
        }

        // ③ 计算 client proof
        guard let salt = Data(base64Encoded: saltB64) else { throw HuaweiError.parse }

        let salted = Self.pbkdf2(password: password, salt: salt, iterations: iterations, keyLen: 32)
        let clientKey = Self.hmac(salted, "Client Key")
        let storedKey = Self.sha256(clientKey)
        let authMessage = "\(firstNonce),\(serverNonce),\(serverNonce)"
        let clientSig = Self.hmac(storedKey, authMessage)
        let proof = Self.xor(clientKey, clientSig)
        let proofB64 = proof.base64EncodedString()

        // ④ 认证
        let authBody = "<request><clientproof>\(proofB64)</clientproof><finalnonce>\(serverNonce)</finalnonce></request>"
        let auth = try await rawRequest("POST", "/api/user/authentication_login", body: authBody)
        try Self.throwIfError(auth)

        loggedIn = true
        // 认证后通常要重新取一次令牌
        if let ses2 = try? await rawRequest("GET", "/api/webserver/SesTokInfo", body: nil) {
            if let s = ses2.text("SesInfo") { sessionCookie = s }
            if let t = ses2.text("TokInfo") { token = t }
        }
    }

    /// 老固件的明文登录（RSA 加密密码）
    private func legacyLogin(user: String, password: String) async throws {
        let pw = Self.rsaEncryptPassword(password) ?? password
        let body = "<request><username>\(user)</username><password>\(pw)</password><password_type>1</password_type></request>"
        let resp = try await rawRequest("POST", "/api/user/login", body: body)
        try Self.throwIfError(resp)
        loggedIn = true
    }

    // MARK: 通用请求

    private func rawRequest(_ method: String, _ path: String, body: String?) async throws -> XMLNode {
        guard let url = URL(string: "http://\(host)\(path)") else { throw HuaweiError.badHost }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            req.setValue(token, forHTTPHeaderField: "__RequestVerificationToken")
        }
        if !sessionCookie.isEmpty {
            req.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }
        if let b = body { req.httpBody = b.data(using: .utf8) }

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw HuaweiError.http(code) }

        let parser = XMLParser(data: data)
        let builder = XMLTreeBuilder()
        parser.delegate = builder
        parser.parse()
        guard let root = builder.root else { throw HuaweiError.parse }
        return root
    }

    /// 请求并检查 error 节点
    private func request(_ method: String, _ path: String, body: String? = nil) async throws -> XMLNode {
        let node = try await rawRequest(method, path, body: body)
        try Self.throwIfError(node)
        return node
    }

    private static func throwIfError(_ node: XMLNode) throws {
        guard let err = node.find("error") else { return }
        let code = err.text("code") ?? "?"
        let msg = err.text("message") ?? ""
        if code == "0" { return }

        // 会话失效
        if code == "125002" || code == "125003" {
            throw HuaweiError.loginFailed("会话已失效")
        }
        throw HuaweiError.device(code: code, message: msg)
    }

    // MARK: 数据（首页用）

    /// 一次性拿首页需要的数据
    func fetchOverview() async -> [String: String] {
        guard loggedIn else { return [:] }
        var v: [String: String] = [:]

        // ① 信号
        if let n = try? await request("GET", "/api/device/signal") {
            // 5G 优先
            let nr = ["nr_rsrp": "rsrp", "nr_rsrq": "rsrq", "nr_sinr": "sinr",
                      "nr_pci": "pci", "nr_band": "band", "nr_nrarfcn": "arfcn",
                      "nr_cell_id": "cellid"]
            var used5G = false
            for (src, dst) in nr {
                if let t = n.text(src) {
                    v[dst] = Self.cleanUnit(t)
                    used5G = true
                }
            }
            if !used5G {
                for (src, dst) in ["rsrp": "rsrp", "rsrq": "rsrq", "sinr": "sinr",
                                   "pci": "pci", "band": "band", "earfcn": "arfcn",
                                   "cell_id": "cellid"] {
                    if let t = n.text(src) { v[dst] = Self.cleanUnit(t) }
                }
            }
            if let r = n.text("rssi") { v["rssi"] = Self.cleanUnit(r) }
        }

        // ② 运行状态
        if let n = try? await request("GET", "/api/monitoring/status") {
            if let t = n.text("CurrentNetworkType") { v["netmode"] = Self.netType(t) }
            if let t = n.text("SignalStrength") { v["signalLevel"] = t }
            if let t = n.text("maxsignal") { v["signalMax"] = t }
            if let t = n.text("ConnectionStatus") { v["connStatus"] = t }
            if let t = n.text("SimStatus") { v["simstatus"] = (t == "1" || t == "0") ? "0" : "1" }
            if let t = n.text("CurrentWifiUser") { v["online"] = t }
            if let t = n.text("TotalWifiUser") { v["onlineMax"] = t }
            if let t = n.text("RoamingStatus") { v["roaming"] = t }
            if let t = n.text("CurrentServiceDomain") { v["domain"] = t }
            if let t = n.text("RegistrationStatus") { v["regstatus"] = (t == "1") ? "0" : "1" }
            if let t = n.text("BatteryPercent") { v["battery"] = t }
            if let t = n.text("BatteryStatus") { v["charging"] = t }
        }

        // ③ 流量
        if let n = try? await request("GET", "/api/monitoring/traffic-statistics") {
            if let t = n.text("CurrentDownloadRate"), let d = Double(t) {
                v["speedRx"] = String(Int(d))          // 字节/秒
            }
            if let t = n.text("CurrentUploadRate"), let d = Double(t) {
                v["speedTx"] = String(Int(d))
            }
            if let t = n.text("TotalDownload") { v["todayRx"] = t }
            if let t = n.text("TotalUpload") { v["todayTx"] = t }
            if let t = n.text("TotalConnectTime") { v["uptime"] = t }
            if let t = n.text("CurrentDownload") { v["sessionRx"] = t }
            if let t = n.text("CurrentUpload") { v["sessionTx"] = t }
        }

        // ④ 本月
        if let n = try? await request("GET", "/api/monitoring/month_statistics") {
            if let t = n.text("CurrentMonthDownload") { v["monthRx"] = t }
            if let t = n.text("CurrentMonthUpload") { v["monthTx"] = t }
            if let d = Double(v["monthRx"] ?? "0"), let u = Double(v["monthTx"] ?? "0") {
                v["monthTotal"] = String(Int(d + u))
            }
            if let t = n.text("MonthDuration") { v["monthDuration"] = t }
        }
        // 今日合计
        if let d = Double(v["todayRx"] ?? "0"), let u = Double(v["todayTx"] ?? "0") {
            v["todayTotal"] = String(Int(d + u))
        }

        // ⑤ 运营商
        if let n = try? await request("GET", "/api/net/current-plmn") {
            if let t = n.text("FullName") { v["carrier"] = t }
            else if let t = n.text("ShortName") { v["carrier"] = t }
            if let t = n.text("Numeric") { v["plmn"] = t }
        }

        // ⑥ 设备信息
        if let n = try? await request("GET", "/api/device/information") {
            if let t = n.text("DeviceName") { v["model"] = t }
            if let t = n.text("SerialNumber") { v["sn"] = t }
            if let t = n.text("Imei") { v["imei"] = t }
            if let t = n.text("Imsi") { v["imsi"] = t }
            if let t = n.text("Iccid") { v["iccid"] = t }
            if let t = n.text("HardwareVersion") { v["hwver"] = t }
            if let t = n.text("SoftwareVersion") { v["swver"] = t }
            if let t = n.text("MacAddress1") { v["mac"] = t }
            if let t = n.text("WebUIVersion") { v["webver"] = t }
            if let t = n.text("DeviceType") { v["deviceType"] = t }
        }

        return v
    }

    /// 轻量：只取速率与今日流量（每秒调用）
    func fetchRates() async -> (rx: Double, tx: Double, todayRx: Double, todayTx: Double, uptime: Int) {
        guard loggedIn else { return (0,0,0,0,0) }
        guard let n = try? await request("GET", "/api/monitoring/traffic-statistics") else {
            return (0,0,0,0,0)
        }
        let rx  = Double(n.text("CurrentDownloadRate") ?? "0") ?? 0
        let tx  = Double(n.text("CurrentUploadRate") ?? "0") ?? 0
        let tRx = Double(n.text("TotalDownload") ?? "0") ?? 0
        let tTx = Double(n.text("TotalUpload") ?? "0") ?? 0
        let up  = Int(n.text("TotalConnectTime") ?? "0") ?? 0
        return (rx, tx, tRx, tTx, up)
    }

    // MARK: 控制

    /// 重启（Control: 1 = 重启）
    func reboot() async -> Bool {
        do {
            _ = try await request("POST", "/api/device/control",
                                  body: "<request><Control>1</Control></request>")
            return true
        } catch {
            lastErrorText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return false
        }
    }

    /// 恢复出厂（Control: 2）
    func factoryReset() async -> Bool {
        do {
            _ = try await request("POST", "/api/device/control",
                                  body: "<request><Control>2</Control></request>")
            return true
        } catch {
            lastErrorText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return false
        }
    }

    /// 移动数据开关
    func setMobileData(_ on: Bool) async -> Bool {
        do {
            _ = try await request("POST", "/api/dialup/mobile-dataswitch",
                                  body: "<request><dataswitch>\(on ? 1 : 0)</dataswitch></request>")
            return true
        } catch {
            lastErrorText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return false
        }
    }

    /// 定时重启
    func setTimedReboot(enable: Bool, start: String, end: String) async -> Bool {
        let body = "<request><TimingReboot>\(enable ? 1 : 0)</TimingReboot>"
            + "<start_time>\(start)</start_time><end_time>\(end)</end_time></request>"
        do {
            _ = try await request("POST", "/api/diagnosis/time_reboot", body: body)
            return true
        } catch {
            lastErrorText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return false
        }
    }

    /// 信号灯
    func setLed(_ on: Bool) async -> Bool {
        do {
            _ = try await request("POST", "/api/led/appctrlled",
                                  body: "<request><ledapp>\(on ? 1 : 0)</ledapp></request>")
            return true
        } catch { return false }
    }

    // MARK: 短信

    struct SmsItem: Identifiable {
        let id = UUID()
        var index: String
        var phone: String
        var content: String
        var date: String
        var read: Bool
        var outgoing: Bool
    }

    func fetchSms(page: Int = 1, count: Int = 20) async -> [SmsItem] {
        let body = """
        <request><PageIndex>\(page)</PageIndex><ReadCount>\(count)</ReadCount>\
        <BoxType>1</BoxType><SortType>0</SortType><Ascending>0</Ascending>\
        <UnreadPreferred>0</UnreadPreferred></request>
        """
        guard let n = try? await request("POST", "/api/sms/sms-list", body: body) else { return [] }

        return n.all("Messages").flatMap { box -> [SmsItem] in
            box.all("Message").map { m in
                SmsItem(index: m.text("Index") ?? "",
                        phone: m.text("Phone") ?? "",
                        content: (m.text("Content") ?? "").replacingOccurrences(of: "&#13;", with: "\n"),
                        date: m.text("Date") ?? "",
                        read: (m.text("Smstat") ?? "0") == "0",
                        outgoing: (m.text("SmsType") ?? "1") == "2")
            }
        }
    }

    func sendSms(to numbers: [String], text: String) async -> Bool {
        let list = numbers.map { "<Phone>\($0)</Phone>" }.joined()
        // 华为要求分号分隔
        let joined = numbers.joined(separator: ";")
        let body = """
        <request><Index>-1</Index><Phones><Phone>\(joined)</Phone></Phones>\
        <Sca></Sca><Content>\(Self.escape(text))</Content><Length>\(text.utf8.count)</Length>\
        <Reserved>1</Reserved><Date>\(Self.nowString())</Date></request>
        """
        _ = list
        do {
            _ = try await request("POST", "/api/sms/send-sms", body: body)
            return true
        } catch {
            lastErrorText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return false
        }
    }

    func deleteSms(indices: [String]) async -> Bool {
        let nums = indices.joined(separator: ";")
        let body = "<request><Index>\(nums)</Index></request>"
        do {
            _ = try await request("POST", "/api/sms/delete-sms", body: body)
            return true
        } catch { return false }
    }

    func markSmsRead(indices: [String]) async -> Bool {
        let nums = indices.joined(separator: ";")
        do {
            _ = try await request("POST", "/api/sms/set-read",
                                  body: "<request><Index>\(nums)</Index></request>")
            return true
        } catch { return false }
    }

    // MARK: 在线设备

    struct HostItem: Identifiable {
        let id = UUID()
        var name: String
        var ip: String
        var mac: String
    }

    func fetchHosts() async -> [HostItem] {
        guard let n = try? await request("GET", "/api/system/HostInfo") else { return [] }
        return n.all("Host").map { h in
            HostItem(name: h.text("HostName") ?? "-",
                     ip: h.text("IpAddress") ?? "-",
                     mac: h.text("MacAddress") ?? "-")
        }
    }

    // MARK: 锁频 / 制式

    /// 当前制式（net-mode）
    func fetchNetMode() async -> (mode: String, sub: String) {
        guard let n = try? await request("GET", "/api/net/net-mode") else { return ("", "") }
        return (n.text("NetworkMode") ?? "", n.text("NetworkBand") ?? "")
    }

    /// 当前锁定
    func fetchLockFreq() async -> [String: String] {
        guard let n = try? await request("GET", "/api/net/lock-freq") else { return [:] }
        var v: [String: String] = [:]
        if let t = n.text("LTEBandLock") { v["lteBand"] = t }
        if let t = n.text("LTEFreqLock") { v["lteFreq"] = t }
        if let t = n.text("NRBandLock") { v["nrBand"] = t }
        if let t = n.text("NRFreqLock") { v["nrFreq"] = t }
        if let t = n.text("NRCellLock") { v["nrCell"] = t }
        return v
    }

    /// 写入锁频
    /// mode: 0 频段 1 频点 2 锁小区 3 解除
    func applyLock(mode: Int, band: String, freq: String,
                   cellBand: String, cellFreq: String, cellPci: String) async -> Bool {
        var nrBand = ""
        var nrFreq = ""
        var nrCell = ""

        switch mode {
        case 0:
            nrBand = band.replacingOccurrences(of: " ", with: "")
        case 1:
            nrFreq = freq.replacingOccurrences(of: " ", with: "")
        case 2:
            // 华为格式：band,freq,pci
            nrCell = "\(cellBand),\(cellFreq),\(cellPci)"
        default:
            break   // 全空 = 解除
        }

        let body = "<request>"
            + "<NRBandLock>\(nrBand)</NRBandLock>"
            + "<NRFreqLock>\(nrFreq)</NRFreqLock>"
            + "<NRCellLock>\(nrCell)</NRCellLock>"
            + "</request>"

        do {
            _ = try await request("POST", "/api/net/lock-freq", body: body)
            return true
        } catch {
            lastErrorText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return false
        }
    }

    /// 邻区列表
    func fetchNeighborCells() async -> [(band: String, pci: String, freq: String, rsrp: String)] {
        guard let n = try? await request("GET", "/api/device/nbrcellinfo") else { return [] }
        return n.all("Cell").map { c in
            (c.text("Band") ?? "-", c.text("PCI") ?? "-",
             c.text("Frequency") ?? "-", c.text("RSRP") ?? "-")
        }
    }

    // MARK: 工具

    static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    static func pbkdf2(password: String, salt: Data, iterations: Int, keyLen: Int) -> Data {
        var out = Data(count: keyLen)
        let pw = Array(password.utf8)
        out.withUnsafeMutableBytes { outBuf in
            salt.withUnsafeBytes { saltBuf in
                _ = CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pw, pw.count,
                    saltBuf.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    outBuf.bindMemory(to: UInt8.self).baseAddress, keyLen)
            }
        }
        return out
    }

    static func hmac(_ key: Data, _ message: String) -> Data {
        let k = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: k)
        return Data(mac)
    }

    static func sha256(_ d: Data) -> Data {
        Data(SHA256.hash(data: d))
    }

    static func xor(_ a: Data, _ b: Data) -> Data {
        var out = Data(count: min(a.count, b.count))
        for i in 0..<out.count { out[i] = a[i] ^ b[i] }
        return out
    }

    /// 去掉 dBm / dB 单位
    static func cleanUnit(_ s: String) -> String {
        s.replacingOccurrences(of: "dBm", with: "")
         .replacingOccurrences(of: "dB", with: "")
         .trimmingCharacters(in: .whitespaces)
    }

    /// 网络类型数字 → 显示
    static func netType(_ t: String) -> String {
        switch t {
        case "19", "101": return "3"      // LTE / 5G
        case "9":         return "2"      // 4G
        default:          return t
        }
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func nowString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }

    /// 老固件的 RSA 密码加密（PKCS#1 v1.5，指数 65537）
    static func rsaEncryptPassword(_ password: String) -> String? {
        return nil   // 新固件走 SCRAM，旧固件极少见，暂不实现
    }
}
