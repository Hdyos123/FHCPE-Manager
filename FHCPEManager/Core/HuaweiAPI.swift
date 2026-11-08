import Foundation
import CryptoKit
import Security


// MARK: - JSON 适配层
//
// 华为桥接返回的是 JSON 对象（{response:{...}} 或数组），
// 但很多解析代码按 XMLNode 的 text()/all() 写。
// JSONNode 提供同样的接口，避免大面积改解析逻辑。
final class JSONNode {
    let name: String
    fileprivate let raw: Any?

    init(name: String = "response", _ raw: Any?) {
        self.name = name
        self.raw = raw
    }

    convenience init(_ obj: [String: Any]) {
        self.init(name: "response", obj["response"] ?? obj)
    }

    /// 取子节点文本（把数字也转字符串）
    func text(_ n: String) -> String? {
        guard let d = raw as? [String: Any], let v = d[n] else { return nil }
        if let s = v as? String { return s.isEmpty ? nil : s }
        if let s = v as? NSNumber { return s.stringValue }
        if let b = v as? Bool { return b ? "1" : "0" }
        return nil
    }

    /// 取原始值（可能是嵌套对象或数组）
    func value(_ n: String) -> Any? {
        (raw as? [String: Any])?[n]
    }

    /// 同名子节点列表
    func all(_ n: String) -> [JSONNode] {
        guard let d = raw as? [String: Any], let v = d[n] else { return [] }
        if let arr = v as? [[String: Any]] {
            return arr.map { JSONNode(name: n, $0) }
        }
        if let obj = v as? [String: Any] {
            let keys = obj.keys.compactMap { Int($0) }.sorted()
            if !keys.isEmpty {
                return keys.compactMap { k in
                    (obj[String(k)] as? [String: Any]).map { JSONNode(name: n, $0) }
                }
            }
            return [JSONNode(name: n, obj)]
        }
        return []
    }

    /// 第 idx 个子节点
    func child(_ n: String) -> JSONNode? {
        guard let d = raw as? [String: Any], let v = d[n] else { return nil }
        return JSONNode(name: n, v)
    }

    /// 自身文本
    func text() -> String? {
        if let s = raw as? String { return s.isEmpty ? nil : s }
        if let n = raw as? NSNumber { return n.stringValue }
        return nil
    }

    /// 递归查找同名节点（兼容旧 XMLNode 写法）
    func find(_ n: String) -> JSONNode? {
        if name == n { return self }
        guard let d = raw as? [String: Any] else { return nil }
        if let v = d[n] { return JSONNode(name: n, v) }
        for (_, v) in d {
            if let sub = v as? [String: Any],
               let r = JSONNode(name: "", sub).find(n) { return r }
            if let arr = v as? [[String: Any]] {
                for item in arr {
                    if let r = JSONNode(name: "", item).find(n) { return r }
                }
            }
        }
        return nil
    }

    var children: [JSONNode] {
        guard let d = raw as? [String: Any] else { return [] }
        return d.map { JSONNode(name: $0.key, $0.value) }
    }
}

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
    internal var lastErrorText: String = ""

    private var sessionCookie: String = ""
    private var token: String = ""
    private var session: URLSession!
    fileprivate(set) var user: String = "admin"

    /// 最近一次登录用的凭据（用于自动重登）
    internal var password: String = ""

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
        self.host = host
        self.user = user
        self.password = password

        // 优先用原生 SCRAM（不依赖页面 JS）
        var ok = await HuaweiBridge.shared.nativeLogin(host: host, user: user, password: password)
        if !ok {
            // 兜底：走页面通道
            ok = await HuaweiBridge.shared.login(host: host, user: user, password: password)
        }
        guard ok else {
            let reason = (await HuaweiBridge.shared.lastError) ?? "无法连接设备"
            lastErrorText = reason
            throw NSError(domain: "Huawei", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: reason])
        }
        loggedIn = true
    }

    /// 别名 → 路径
    private static let aliasPath: [String: String] = [
        "singal": "/api/device/signal",
        "monitoringStatus": "/api/monitoring/status",
        "monitoringTraffic": "/api/monitoring/traffic-statistics",
        "mounthTraffic": "/api/monitoring/month_statistics",
        "dialyTraffic": "/api/monitoring/daily-data-limit",
        "netCurrentPlmn": "/api/net/current-plmn",
        "hostList": "/api/wlan/host-list",
        "wlanStatusSwitch": "/api/wlan/wlan-switch",
        "netMode": "/api/net/net-mode",
        "pinStatus": "/api/pin/status",
        "wanInfo": "/api/ntwk/dualwaninfo",
        "deviceInformation": "/api/device/information",
        "convergedStatus": "/api/monitoring/converged-status",
    ]

    /// 取数据：优先原生（SCRAM 登录后），失败再走页面
    func bridgeGet(_ alias: String) async -> [String: Any] {
        if let path = Self.aliasPath[alias] {
            let r = await HuaweiBridge.shared.nativeGetPath(path)
            if !r.isEmpty { return r }
        }
        return await HuaweiBridge.shared.get(alias)
    }

    /// 通过桥接提交
    func bridgePost(_ alias: String, _ body: [String: Any]) async -> [String: Any] {
        await HuaweiBridge.shared.post(alias, body)
    }

    func lockState() async throws -> (locked: Bool, minutes: Int) {
        let n = try await rawRequest("GET", "/api/user/state-login", body: nil)
        let locked = (n.text("lockstatus") ?? "0") == "1"
        let waitStr = n.text("remainwaittime") ?? "0"
        let minutes = Int(waitStr) ?? 0
        return (locked, minutes)
    }

    /// 重新获取会话 Cookie 与 CSRF token
    private func refreshToken() async throws {
        let ses = try await rawRequest("GET", "/api/webserver/SesTokInfo", body: nil)
        if let s = ses.text("SesInfo") {
            let c = Self.cookieOnly(s)
            if !c.isEmpty { sessionCookie = c }
        }
        if let t = ses.text("TokInfo") { token = t }
        if sessionCookie.isEmpty { throw HuaweiError.noSession }
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
        req.setValue("http://\(host)/html/index.html", forHTTPHeaderField: "Referer")
        req.setValue("http://\(host)", forHTTPHeaderField: "Origin")
        if !token.isEmpty {
            req.setValue(token, forHTTPHeaderField: "__RequestVerificationToken")
        }
        if !sessionCookie.isEmpty {
            req.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }
        if let b = body {
            // 华为后端对带 XML 声明的报文兼容性更好
            let full = b.hasPrefix("<?xml") ? b : "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + b
            req.httpBody = full.data(using: .utf8)
        }

        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        let code = http?.statusCode ?? 0

        // 设备可能通过 Set-Cookie 下发新会话，必须跟上
        // 注意：allHeaderFields 值可能是 String 也可能是 Array<String>
        if let headers = http?.allHeaderFields {
            for (k, v) in headers {
                let key = (k as? String) ?? "\(k)"
                guard key.lowercased() == "set-cookie" else { continue }

                var raws: [String] = []
                if let s = v as? String {
                    raws = s.components(separatedBy: ",SessionID=")
                        .enumerated()
                        .map { $0.offset > 0 ? "SessionID=" + $0.element : $0.element }
                } else if let arr = v as? [String] {
                    raws = arr
                } else {
                    raws = ["\(v)"]
                }

                for raw in raws {
                    let cookie = Self.cookieOnly(raw)
                    if !cookie.isEmpty { sessionCookie = cookie }
                }
            }
        }

        guard code == 200 else { throw HuaweiError.http(code) }

        let parser = XMLParser(data: data)
        let builder = XMLTreeBuilder()
        parser.delegate = builder
        parser.parse()
        guard let root = builder.root else { throw HuaweiError.parse }
        return root
    }

    /// 请求并检查 error 节点
    /// 兼容层：所有请求都改由页面代发（华为的加密无法在原生侧复刻）
    internal func request(_ method: String, _ path: String, body: String? = nil) async throws -> JSONNode {
        // body 是 XML 字符串，要转成 JSON 对象给页面
        var dict: [String: Any] = [:]
        if let b = body {
            dict = Self.xmlToDict(b)
        }

        let result: [String: Any]
        if method.uppercased() == "GET" {
            result = await HuaweiBridge.shared.getPath(path)
        } else {
            result = await HuaweiBridge.shared.postPath(path, dict)
        }

        if let err = result["__err"] as? String {
            lastErrorText = err
            throw HuaweiError.http(Int(err) ?? 0)
        }
        if let e = result["error"] as? [String: Any],
           let code = e["code"] {
            lastErrorText = "\(code)"
            throw HuaweiError.http(Int("\(code)") ?? 0)
        }
        return JSONNode(result)
    }

    /// 极简 XML → 字典（用于把 POST body 交给页面）
    static func xmlToDict(_ xml: String) -> [String: Any] {
        var dict: [String: Any] = [:]
        let parser = XMLParser(data: Data(xml.utf8))
        let b = XMLTreeBuilder()
        parser.delegate = b
        parser.parse()
        guard let root = b.root else { return dict }
        for c in root.children {
            if c.children.isEmpty {
                dict[c.name] = c.value
            } else {
                dict[c.name] = recursiveDict(c)
            }
        }
        return dict
    }

    private static func recursiveDict(_ node: XMLNode) -> Any {
        if node.children.isEmpty { return node.value }
        // 子节点同名 → 数组
        let names = node.children.map { $0.name }
        if Set(names).count == 1 && names.count > 1 {
            return node.children.map { recursiveDict($0) }
        }
        var d: [String: Any] = [:]
        for c in node.children {
            d[c.name] = c.children.isEmpty ? c.value : recursiveDict(c)
        }
        return d
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

        // ① 信号（华为字段带 nr 前缀，单位含在值里）
        let sig = await bridgeGet("singal")
        if let err = sig["__err"] as? String {
            v["__sigErr"] = err
        } else {
            func put(_ src: String, _ dst: String) {
                if let t = sig[src] as? String, !t.isEmpty {
                    v[dst] = Self.cleanUnit(t)
                }
            }
            put("nrrsrp", "rsrp")
            put("nrrsrq", "rsrq")
            put("nrrssi", "rssi")
            put("nrsinr", "sinr")
            put("nrearfcn", "arfcn")
            put("pci", "pci")
            put("cell_id", "cellid")
            put("nrcqi0", "qci")

            // 频段形如 "100MHz@627264(N78)"
            if let band = sig["bandInfo"] as? String, !band.isEmpty {
                v["band"] = band.uppercased().replacingOccurrences(of: "N", with: "")
                    .replacingOccurrences(of: "B", with: "")
            }
            if let bw = sig["nrulbandwidth"] as? String, !bw.isEmpty {
                v["bw"] = bw
            }
            // 层数 / MCS
            if let r = sig["nrrank"] as? String, !r.isEmpty { v["rank"] = r }
            if let m = sig["nrulmcs"] as? String, !m.isEmpty { v["ulmcs"] = m }
            if let m = sig["nrdlmcs"] as? String, !m.isEmpty { v["dlmcs"] = m }
            if let p = sig["nrtxpower"] as? String, !p.isEmpty { v["txpower"] = p }
            if let b = sig["nrbler"] as? String, !b.isEmpty { v["bler"] = b }
            if let m = sig["mode"] as? String, !m.isEmpty { v["mode"] = m }
            if let t = sig["tac"] as? String, !t.isEmpty { v["tac"] = t }
            if let p = sig["plmn"] as? String, !p.isEmpty { v["plmn"] = p }
        }

        // ② 运行状态
        let st = await bridgeGet("monitoringStatus")
        if let t = st["CurrentNetworkType"] as? String { v["netmode"] = Self.netType(t) }
        if let t = st["SignalIconNr"] as? String { v["signalIcon"] = t }
            else if let t = st["SignalIcon"] as? String { v["signalIcon"] = t }
        if let t = st["maxsignal"] as? String { v["signalMax"] = t }
        if let t = st["ConnectionStatus"] as? String {
            v["connStatus"] = t
            v["regstatus"] = (t == "901") ? "0" : "1"
        }
        if let t = st["SimStatus"] as? String { v["simstatus"] = (t == "1") ? "0" : "1" }
        if let t = st["CurrentWifiUser"] as? String { v["online"] = t }
        if let t = st["TotalWifiUser"] as? String { v["onlineMax"] = t }
        if let t = st["RoamingStatus"] as? String { v["roaming"] = t }
        if let t = st["BatteryPercent"] as? String, !t.isEmpty { v["battery"] = t }
        if let t = st["flymode"] as? String { v["airplane"] = t }

        // ③ 实时与累计流量
        let tr = await bridgeGet("monitoringTraffic")
        if let t = tr["CurrentDownloadRate"] as? String, let d = Double(t) {
            v["speedRx"] = String(Int(d))     // 字节/秒
        }
        if let t = tr["CurrentUploadRate"] as? String, let d = Double(t) {
            v["speedTx"] = String(Int(d))
        }
        if let t = tr["TotalDownload"] as? String { v["totalRx"] = t }
        if let t = tr["TotalUpload"] as? String { v["totalTx"] = t }
        if let t = tr["CurrentDownload"] as? String { v["sessionRx"] = t }
        if let t = tr["CurrentUpload"] as? String { v["sessionTx"] = t }
        if let t = tr["CurrentConnectTime"] as? String, let n = Int(t) {
            v["uptime"] = String(n)
        }

        // ④ 本月
        let mo = await bridgeGet("mounthTraffic")
        if let t = mo["CurrentMonthDownload"] as? String { v["monthRx"] = t }
        if let t = mo["CurrentMonthUpload"] as? String { v["monthTx"] = t }
        if let d = Double(v["monthRx"] ?? "0"), let u = Double(v["monthTx"] ?? "0") {
            v["monthTotal"] = String(Int(d + u))
        }
        if let t = mo["CurrentDayUsed"] as? String, let n = Double(t) {
            v["todayUsed"] = String(Int(n))
        }
        if let t = mo["MonthLastClearTime"] as? String { v["monthStart"] = t }

        // ⑤ 运营商
        let pl = await bridgeGet("netCurrentPlmn")
        if let t = pl["FullName"] as? String, !t.isEmpty { v["carrier"] = t }
        else if let t = pl["ShortName"] as? String, !t.isEmpty { v["carrier"] = t }
        if let t = pl["Numeric"] as? String { v["plmn"] = t }

        // ⑥ 设备信息
        let di = await bridgeGet("deviceInformation")
        if let t = di["DeviceName"] as? String { v["model"] = t }
            else if let t = di["devicename"] as? String { v["model"] = t }
        if let t = di["SerialNumber"] as? String { v["sn"] = t }
        if let t = di["Imei"] as? String { v["imei"] = t }
        if let t = di["Imsi"] as? String { v["imsi"] = t }
        if let t = di["Iccid"] as? String { v["iccid"] = t }
        if let t = di["HardwareVersion"] as? String { v["hwver"] = t }
        if let t = di["SoftwareVersion"] as? String { v["swver"] = t }
        if let t = di["MacAddress1"] as? String { v["mac"] = t }
        if let t = di["DeviceType"] as? String { v["deviceType"] = t }

        // 设备扩展信息（硬件版本等）
        let ex = await bridgeGet("systemDeviceinfoex")
        if v["hwver"] == nil, let t = ex["HardwareVersion"] as? String { v["hwver"] = t }
        if let cust = ex["custinfo"] as? [String: Any],
           let n = cust["CustDeviceName"] as? String, !n.isEmpty {
            v["model"] = n
        }
        if let t = ex["UpTime"] as? String { v["uptime2"] = t }

        // ⑦ WLAN 状态
        let wl = await bridgeGet("wlanStatusSwitch")
        if let radios = wl["radios"] as? [[String: Any]] {
            for (i, r) in radios.enumerated() {
                let key = (i == 0) ? "ssid24" : "ssid5g"
                if let s = r["Ssid"] as? String { v[key] = s }
                if let e = r["WifiEnable"] as? String {
                    v[(i == 0) ? "wifi24" : "wifi5g"] = e
                }
            }
            v["wifiCount"] = String(radios.count)
        }

        // ⑧ 连接信息（WAN IP）
        let cn = await bridgeGet("connection")
        if let t = cn["IPv4Address"] as? String { v["wanIP"] = t }
        if let t = cn["RoamAutoConnectEnable"] as? String { v["roamAuto"] = t }

        // ⑨ 网络模式
        let nm = await bridgeGet("netMode")
        if let t = nm["NetworkMode"] as? String { v["netModeRaw"] = t }
        if let t = nm["NetworkBand"] as? String { v["netBand"] = t }

        return v
    }

    /// 轻量：只取速率与今日流量（每秒调用）
    func fetchRates() async -> (rx: Double, tx: Double, todayRx: Double, todayTx: Double, uptime: Int) {
        guard loggedIn else { return (0,0,0,0,0) }
        let t = await bridgeGet("monitoringTraffic")
        func d(_ k: String) -> Double {
            Double((t[k] as? String) ?? "0") ?? 0
        }
        return (d("CurrentDownloadRate"), d("CurrentUploadRate"),
                d("TotalDownload"), d("TotalUpload"),
                Int(d("CurrentConnectTime")))
    }

    // MARK: 控制

    /// 重启（Control: 1 = 重启）
    func reboot() async -> Bool {
        do {
            let r = await bridgePost("deviceControl", ["Control": 1])
            return r["__err"] == nil
        } catch {
            lastErrorText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return false
        }
    }

    /// 恢复出厂（Control: 2）
    func factoryReset() async -> Bool {
        do {
            let r = await bridgePost("deviceControl", ["Control": 2])
            return r["__err"] == nil
        } catch {
            lastErrorText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return false
        }
    }

    /// 移动数据开关
    func setMobileData(_ on: Bool) async -> Bool {
        do {
            let r = await bridgePost("homeDataSwitch", ["dataswitch": on ? 1 : 0])
            return r["__err"] == nil
        } catch {
            lastErrorText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return false
        }
    }

    /// 定时重启
    func setTimedReboot(enable: Bool, start: String, end: String) async -> Bool {
        do {
            let r = await bridgePost("timeReboot", [
                "TimingReboot": enable ? 1 : 0,
                "start_time": start, "end_time": end
            ])
            return r["__err"] == nil
        } catch {
            lastErrorText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return false
        }
    }

    /// 信号灯
    func setLed(_ on: Bool) async -> Bool {
        do {
            let r = await bridgePost("ledApplyCtrl", ["ledapp": on ? 1 : 0])
            return r["__err"] == nil
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
        let rr = await bridgePost("smsList", [
            "PageIndex": page, "ReadCount": count,
            "BoxType": 1, "SortType": 0, "Ascending": 0, "UnreadPreferred": 0
        ])
        guard rr["__err"] == nil else { return [] }
        let n = JSONNode(rr)

        return n.all("Message").map { m in
                SmsItem(index: m.text("Index") ?? "",
                        phone: m.text("Phone") ?? "",
                        content: (m.text("Content") ?? "").replacingOccurrences(of: "&#13;", with: "\n"),
                        date: m.text("Date") ?? "",
                        read: (m.text("Smstat") ?? "0") == "0",
                        outgoing: (m.text("SmsType") ?? "1") == "2")
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
        _ = body
        do {
            let r = await bridgePost("sendSms", [
                "Index": -1,
                "Phones": ["Phone": [joined]],
                "Sca": "", "Content": text,
                "Length": text.utf8.count, "Reserved": 1,
                "Date": Self.nowString()
            ])
            return r["__err"] == nil
        } catch {
            lastErrorText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return false
        }
    }

    func deleteSms(indices: [String]) async -> Bool {
        let nums = indices.joined(separator: ";")
        _ = nums
        do {
            let r = await bridgePost("deleteSms", ["Index": indices.joined(separator: ";")])
            return r["__err"] == nil
        } catch { return false }
    }

    func markSmsRead(indices: [String]) async -> Bool {
        _ = indices
        do {
            let r = await bridgePost("setSmsRead", ["Index": indices.joined(separator: ";")])
            return r["__err"] == nil
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
        let list = await HuaweiBridge.shared.getList("hostList")
        return list.compactMap { h in
            let name = (h["HostName"] as? String) ?? "-"
            let ip = (h["IpAddress"] as? String) ?? "-"
            let mac = (h["MacAddress"] as? String) ?? "-"
            guard mac != "-" || ip != "-" else { return nil }
            return HostItem(name: name.isEmpty ? "设备" : name, ip: ip, mac: mac)
        }
    }

    // MARK: 锁频 / 制式

    /// 当前制式（net-mode）
    func fetchNetMode() async -> (mode: String, sub: String) {
        let m = await bridgeGet("netMode")
        return ((m["NetworkMode"] as? String) ?? "", (m["NetworkBand"] as? String) ?? "")
    }

    /// 当前锁定
    func fetchLockFreq() async -> [String: String] {
        // H153 固件的 lock-freq 接口未开放，锁定状态由 netMode 反映
        var v: [String: String] = [:]
        let m = await bridgeGet("netMode")
        if let t = m["LTEBand"] as? String, !t.isEmpty { v["lteBand"] = t }
        if let t = m["NetworkBand"] as? String, !t.isEmpty { v["nrBand"] = t }
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

        do {
            let r = await bridgePost("lockFreq", [
                "NRBandLock": nrBand,
                "NRFreqLock": nrFreq,
                "NRCellLock": nrCell
            ])
            if let e = r["__err"] {
                lastErrorText = "\(e)"
                return false
            }
            return true
        }
    }

    /// 邻区列表
    func fetchNeighborCells() async -> [(band: String, pci: String, freq: String, rsrp: String)] {
        // H153 固件未开放 nbrcellinfo
        return []
    }

    // MARK: 工具

    /// 从 "SessionID=abc;Path=/;HttpOnly" 里只取 "SessionID=abc"
    static func cookieOnly(_ raw: String) -> String {
        let first = raw.split(separator: ";").first.map(String.init) ?? raw
        let t = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.contains("=") ? t : ""
    }

    /// 把设备错误码翻译成中文
    static func hintFor(_ node: XMLNode, code: String) -> String {
        let wait = node.find("error")?.text("tobelockedtime")
            ?? node.find("error")?.text("remainwaittime")
        let remain = node.find("error")?.text("remaincount")

        switch code {
        case "108006", "108001", "108002":
            var h = "账号或密码不正确"
            if let r = remain { h += "，还可再试 \(r) 次" }
            if let w = wait, w != "0" { h += "。设备已锁定 \(w) 分钟" }
            return h
        case "108007":
            var h = "密码错误次数过多，设备已锁定"
            if let w = wait, w != "0" { h += "，请等待 \(w) 分钟" }
            return h
        case "108003":
            return "该账号已登录，请先在其它设备退出"
        case "116001":
            return "登录已过期，请重试"
        case "125002", "125003":
            return "会话失效，请重试"
        default:
            let m = node.find("error")?.text("message") ?? ""
            return m.isEmpty ? "设备返回错误 \(code)" : "\(m)（\(code)）"
        }
    }

    /// 十六进制字符串 → Data
    static func hexToData(_ s: String) -> Data? {
        guard s.count % 2 == 0 else { return nil }
        var d = Data(capacity: s.count / 2)
        var idx = s.startIndex
        while idx < s.endIndex {
            let nxt = s.index(idx, offsetBy: 2)
            guard let b = UInt8(s[idx..<nxt], radix: 16) else { return nil }
            d.append(b)
            idx = nxt
        }
        return d
    }

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
