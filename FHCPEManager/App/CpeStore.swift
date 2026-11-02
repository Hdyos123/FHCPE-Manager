import Foundation
import SwiftUI

@MainActor
final class CpeStore: ObservableObject {
    @Published var status = CpeStatus()
    @Published var hosts: [CpeHost] = []
    @Published var carriers: [CarrierComponent] = []

    /// 流量增量（距上次设备计数变化），单位字节
    @Published var todayRxDelta: Double = 0
    @Published var todayTxDelta: Double = 0
    /// 设备流量计数器上次变化的时间，用于显示「xx 秒更新」
    @Published var trafficUpdatedAt: Date?

    private var lastTodayTotal: Double = 0
    /// OPPO 累计流量基准（字节）
    private var lastOppoRx: Double = 0
    private var lastOppoTx: Double = 0
    /// 速率采样窗口（避免某些秒字节数没变导致显示 0）
    private var speedSamples: [(t: Date, rx: Double, tx: Double)] = []
    /// 华为慢变数据缓存
    private var hwSlowCache: [String: String] = [:]
    private var hwSlowAt: Date = .distantPast

    /// OPPO 慢变数据缓存（信号/小区/设备），避免每秒触发页面重排
    private var oppoSlowCache: [String: String] = [:]
    private var oppoSlowAt: Date = .distantPast
    private let oppoSlowInterval: TimeInterval = 5
    @Published var smsList: [CpeSms] = []
    @Published var isLoggedIn = false
    /// 当前连接的设备
    @Published var activeProfile: CpeProfile?

    /// 检测到另一台可用设备（用于提醒切换）
    @Published var detectedProfile: CpeProfile?
    /// 当前设备是否已断开（连续探测失败）
    @Published var currentOffline = false
    var isOppo: Bool { activeProfile?.vendor == .oppo }
    var isHuawei: Bool { activeProfile?.vendor == .huawei }
    var isFiberHome: Bool { activeProfile?.vendor == .fiberhome }
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var toastText: String?
    private var toastTask: Task<Void, Never>?

    @Published var toastKind: ToastKind = .success

    /// 顶部短暂提示
    func toast(_ msg: String, kind: ToastKind = .success) {
        // 同时给出触感
        switch kind {
        case .success: Haptic.success()
        case .info:    Haptic.light()
        case .error:   Haptic.error()
        }
        toastTask?.cancel()
        toastKind = kind
        toastText = msg
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { self.toastText = nil }
        }
    }
    @Published var lastUpdate = Date()

    @Published var realtimeRx: Double = 0
    @Published var realtimeTx: Double = 0

    @Published var refreshInterval: Double {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "cpe.rateMs") }
    }

    private let bridge = CpeBridge.shared
    private var pollTask: Task<Void, Never>?
    private var lastTick = Date()

    /// 连续失败次数
    private var _failStreak = 0
    private var failStreak: Int {
        get { _failStreak }
        set { _failStreak = newValue }
    }

    /// 会话失效时自动重新登录一次
    func reloginIfNeeded() async {
        let cfg = Settings.load()
        guard !cfg.password.isEmpty else { return }

        // 重试 3 次（间隔 1.5s），避免瞬时抖动就弹出错误提示
        for attempt in 1...3 {
            let ok = await login(host: cfg.host, user: cfg.user, password: cfg.password)
            if ok { return }
            if attempt < 3 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }

        // 三次都失败才提示，且用温和措辞
        toast("暂时连不上设备，稍后自动重试", kind: .info)
    }

    private var useNative = false
    @Published var diagLog = ""

    init() {
        let saved = UserDefaults.standard.double(forKey: "cpe.rateMs")
        refreshInterval = saved > 0 ? saved : 1.0
    }

    // MARK: - 登录

    /// 使用设备档案登录（自动按厂商分流）
    func login(profile: CpeProfile) async -> Bool {
        activeProfile = profile
        switch profile.vendor {
        case .oppo:     return await loginOppo(profile)
        case .huawei:   return await loginHuawei(profile)
        case .fiberhome:
            return await login(host: profile.host, user: profile.user, password: profile.password)
        }
    }

    /// 华为登录：SCRAM 明文 XML（无加密）
    private func loginHuawei(_ profile: CpeProfile) async -> Bool {
        errorText = nil
        isLoading = true
        defer { isLoading = false }
        clearAll()

        do {
            try await HuaweiAPI.shared.login(host: profile.host,
                                             user: profile.user,
                                             password: profile.password)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "登录失败"
            return false
        }

        // 取一次数据确认可用
        var d: [String: String] = [:]
        for _ in 1...4 {
            d = await HuaweiAPI.shared.fetchOverview()
            if !d.isEmpty { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard !d.isEmpty else {
            errorText = "登录成功但读不到数据"
            return false
        }

        ProfileStore.upsert(profile)
        ProfileStore.activeID = profile.id
        isLoggedIn = true
        await fetchStatus()
        return true
    }

    /// OPPO 登录：WebView 桥接
    private func loginOppo(_ profile: CpeProfile) async -> Bool {
        errorText = nil
        isLoading = true
        defer { isLoading = false }

        clearAll()
        let ok = await OppoBridge.shared.login(host: profile.host,
                                               user: profile.user,
                                               password: profile.password)
        guard ok else {
            errorText = OppoBridge.shared.lastError ?? "登录失败"
            return false
        }

        // 取一次数据确认可用（页面刚跳转可能需要时间渲染）
        var d: [String: String] = [:]
        for attempt in 1...8 {
            d = await OppoBridge.shared.fetchDashboard()
            if !d.isEmpty { break }
            if attempt < 8 {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        guard !d.isEmpty else {
            errorText = "登录成功但读不到数据，请在诊断页查看桥接日志"
            return false
        }

        // OPPO 单独去重（每次登录 UUID 会变）
        ProfileStore.upsertOppo(profile)
        ProfileStore.activeID = profile.id
        isLoggedIn = true
        await fetchStatus()
        return true
    }

    /// 切换设备前清空状态
    private func clearAll() {
        status = CpeStatus()
        hosts = []
        carriers = []
        realtimeRx = 0
        realtimeTx = 0
        todayRxDelta = 0
        todayTxDelta = 0
        lastOppoRx = 0
        lastOppoTx = 0
        speedSamples.removeAll()
        detectedProfile = nil
        currentOffline = false
        offlineStreak = 0
        oppoSlowCache = [:]
        oppoSlowAt = .distantPast
        hwSlowCache = [:]
        hwSlowAt = .distantPast
        lastTodayTotal = 0
        trafficUpdatedAt = Date()
    }

    func login(host: String, user: String, password: String) async -> Bool {
        errorText = nil
        diagLog = ""
        isLoading = true
        defer { isLoading = false }

        // 切换到新设备前清空旧数据，避免型号/信号残留
        let prevHost = Settings.load().host
        if prevHost != host {
            status = CpeStatus()
            hosts = []
            carriers = []
            realtimeRx = 0
            realtimeTx = 0
            CpeNativeAPI.trace = []
        }

        // 前置校验
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorText = "请填写设备地址"; return false
        }
        guard !user.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorText = "请填写账号"; return false
        }
        guard !password.isEmpty else {
            errorText = "请输入密码"; return false
        }

        // ① 先用原生 API（最直接可控，能准确拿到错误码）
        CpeNativeAPI.shared.configure(host: host, user: user, pass: password)
        do {
            try await CpeNativeAPI.shared.login()

            // 登录已成功，等网络稳定后取数据（最多重试 4 次）
            var probe: [String: String] = [:]
            for attempt in 1...4 {
                probe = (try? await CpeNativeAPI.shared.values(CpeNode.overview)) ?? [:]
                if !probe.isEmpty { break }
                if attempt < 4 {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
            }

            if !probe.isEmpty {
                useNative = true
                Settings(host: host, user: user, password: password).save()
                isLoggedIn = true
                await fetchAll()
                return true
            }

            // 登录成功但取不到数据：不算密码错误，提示网络问题
            diagLog = "原生登录成功但取不到数据"
            errorText = "登录成功但读不到数据，请确认已连接 CPE 的 Wi-Fi"
            return false
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // 凭据错误 / 锁定：直接返回，不再尝试其它路径
            // （避免继续累计失败次数）
            if msg.contains("密码") || msg.contains("账号") || msg.contains("锁定") {
                errorText = msg
                return false
            }
            diagLog = "原生: " + msg
        }

        // ② 原生失败再试 WebView
        let ok = await bridge.login(host: host, user: user, password: password)
        if ok {
            let probe = await bridge.fetchValues(CpeNode.overview)
            if !probe.isEmpty {
                useNative = false
                Settings(host: host, user: user, password: password).save()
                isLoggedIn = true
                await fetchAll()
                return true
            }
            diagLog += " | WebView 登录成功但取不到数据"
        } else {
            diagLog += " | WebView: " + (bridge.lastError ?? "未知")
        }

        errorText = diagLog.isEmpty ? "连接失败" : diagLog
        return false
    }

    func tryAutoLogin() async {
        // 自动登录开关关闭则不尝试
        let auto = UserDefaults.standard.object(forKey: "autoLogin") as? Bool ?? true
        guard auto else { return }

        // 迁移旧的单设备配置
        ProfileStore.migrateIfNeeded()
        // 清理重复档案（同厂商+同地址只保留一条）
        ProfileStore.dedupe()

        // 优先用上次选中的设备
        if let p = ProfileStore.active, !p.password.isEmpty {
            let ok = await login(profile: p)
            if ok { return }
        }

        // 兜底：试第一个可用档案
        for p in ProfileStore.loadAll() where !p.password.isEmpty {
            if await login(profile: p) { return }
        }
    }

    // MARK: - 数据

    func fetchAll() async {
        async let a: Void = fetchStatus()
        async let b: Void = fetchHosts()
        async let c: Void = fetchCarriers()
        _ = await (a, b, c)
        lastUpdate = Date()
    }


    // MARK: - 统一数据入口（自动分流 WebView / 原生）

    func mp(_ method: String, _ data: [String: Any]) async -> [[String: Any]] {
        if useNative {
            return (try? await CpeNativeAPI.shared.multipost(method: method, data: data)) ?? []
        }
        return await bridge.multipost(method: method, data: data)
    }

    func set1(_ url: String, _ value: String) async -> Bool {
        if useNative {
            do { try await CpeNativeAPI.shared.setSingle(url: url, value: value); return true }
            catch { return false }
        }
        return await bridge.setSingle(url: url, value: value)
    }

    func fetchStatus() async {
        // 华为：明文 XML 接口
        if isHuawei {
            // 慢变数据（信号/设备信息/本月）：每 5 秒
            var v = hwSlowCache
            if Date().timeIntervalSince(hwSlowAt) > 5 || v.isEmpty {
                let d = await HuaweiAPI.shared.fetchOverview()
                if !d.isEmpty {
                    v = d
                    hwSlowCache = v
                    hwSlowAt = Date()
                }
            }

            // 快变数据（速率/今日流量）：每次轮询
            let r = await HuaweiAPI.shared.fetchRates()
            if r.rx > 0 || r.tx > 0 || r.todayRx > 0 {
                realtimeRx = r.rx * 8
                realtimeTx = r.tx * 8
                v["speedRx"] = String(Int(r.rx))
                v["speedTx"] = String(Int(r.tx))
                v["todayRx"] = String(Int(r.todayRx))
                v["todayTx"] = String(Int(r.todayTx))
                v["todayTotal"] = String(Int(r.todayRx + r.todayTx))
                if r.uptime > 0 { v["uptime"] = String(r.uptime) }
            }

            status.raw = v
            return
        }

        // OPPO 设备：走 WebView 桥接，解析首页文本
        if isOppo {
            // ── 慢变数据（信号/小区/流量）：每 5 秒一次 ──
            var v = oppoSlowCache
            if Date().timeIntervalSince(oppoSlowAt) > oppoSlowInterval || v.isEmpty {
                let d = await OppoBridge.shared.fetchDashboard()
                if !d.isEmpty {
                    v = OppoParser.normalize(d)
                    // 首个采样前，先用页面的速率值垫着（避免显示 0）
                    if speedSamples.isEmpty {
                        if let r = v["speedRx"], let n = Double(r), n > 0 {
                            realtimeRx = n * 8
                        }
                        if let t = v["speedTx"], let m = Double(t), m > 0 {
                            realtimeTx = m * 8
                        }
                    }
                    oppoSlowCache = v
                    oppoSlowAt = Date()

                    // 流量增量（页面累计值，单位字节）
                    let rxB = Double(v["monthRx"] ?? "") ?? 0
                    let txB = Double(v["monthTx"] ?? "") ?? 0
                    if lastOppoRx > 0, rxB > lastOppoRx {
                        todayRxDelta += rxB - lastOppoRx
                        todayTxDelta += max(0, txB - lastOppoTx)
                        trafficUpdatedAt = Date()
                    }
                    lastOppoRx = rxB
                    lastOppoTx = txB
                }
            }

            // ── 实时速率：累计字节差 ÷ 时间（用 3 秒滑动窗口，避免忽高忽低）──
            let bytes = await OppoBridge.shared.fetchBytes()
            let now = Date()
            if bytes.rx > 0 || bytes.tx > 0 {
                speedSamples.append((now, bytes.rx, bytes.tx))
                // 只保留最近 3 秒的样本
                while speedSamples.count > 2,
                      now.timeIntervalSince(speedSamples[0].t) > 3.0 {
                    speedSamples.removeFirst()
                }

                if let first = speedSamples.first, speedSamples.count >= 2 {
                    let dt = now.timeIntervalSince(first.t)
                    if dt > 0.8 {
                        let rxBps = max(0, (bytes.rx - first.rx) / dt)
                        let txBps = max(0, (bytes.tx - first.tx) / dt)
                        realtimeRx = rxBps * 8
                        realtimeTx = txBps * 8
                        v["speedRx"] = String(Int(rxBps))
                        v["speedTx"] = String(Int(txBps))
                    }
                }
            }

            status.raw = v
            return
        }

        var v: [String: String] = [:]
        var failed = false

        if useNative {
            do {
                v = try await CpeNativeAPI.shared.values(CpeNode.overview)
            } catch {
                failed = true
            }
        } else {
            v = await bridge.fetchValues(CpeNode.overview)
            if v.isEmpty { failed = true }
        }

        // 连续失败计数：超过 2 次就重新登录，恢复被设备踢掉的会话
        if failed || v.isEmpty {
            failStreak += 1
            if failStreak >= 2 {
                failStreak = 0
                await reloginIfNeeded()
            }
            return
        }
        failStreak = 0

        // uptime 需用 $post + get_cmd_result_web（multipost 会 400）
        var up: [String: Any] = [:]
        if useNative {
            up = (try? await CpeNativeAPI.shared.post(
                "get_cmd_result_web", ["key": "UPTIME"])) ?? [:]
        } else {
            up = await bridge.post("get_cmd_result_web", ["key": "UPTIME"])
        }
        if let r = up["result"] as? String {
            v["uptime"] = r
        } else if let n = up["result"] as? NSNumber {
            v["uptime"] = n.stringValue
        }

        status.raw = v
        realtimeRx = status.realtimeRx
        realtimeTx = status.realtimeTx

        // ── 流量增量追踪 ──
        let total = status.double("todayTotal")
        if total > 0 {
            if lastTodayTotal > 0 && total > lastTodayTotal {
                let delta = total - lastTodayTotal
                // 按本月上下行比例拆分增量
                let mRx = status.double("monthRx"), mTx = status.double("monthTx")
                let sum = mRx + mTx
                if sum > 0 {
                    todayRxDelta += delta * mRx / sum
                    todayTxDelta += delta * mTx / sum
                }
                trafficUpdatedAt = Date()
            }
            lastTodayTotal = total
        }
    }

    /// 重置增量（用户手动清空时调用）
    func resetTrafficDelta() {
        todayRxDelta = 0
        todayTxDelta = 0
        lastOppoRx = 0
        lastOppoTx = 0
        speedSamples.removeAll()
        detectedProfile = nil
        currentOffline = false
        offlineStreak = 0
        oppoSlowCache = [:]
        oppoSlowAt = .distantPast
        hwSlowCache = [:]
        hwSlowAt = .distantPast
        lastTodayTotal = 0
        trafficUpdatedAt = Date()
    }

    func fetchHosts() async {
        // 统一入口：返回 {"data":[...]} 结构
        func q(_ url: String, _ node: [String: Any]) async -> [[String: Any]] {
            let obj: [String: Any]
            if useNative {
                obj = (try? await CpeNativeAPI.shared.post(
                    "get_xml_childnode_value", ["url": url, "node": node])) ?? [:]
            } else {
                obj = await bridge.post("get_xml_childnode_value",
                                        ["url": url, "node": node])
            }
            return (obj["data"] as? [[String: Any]]) ?? []
        }

        // 1. Wi-Fi 关联设备
        let wifiRows = await q("LANDevice.1.WLANConfiguration.", [
            "SSID": "SSID",
            "Channel": "Channel",
            "OperatingFrequencyBand": "OperatingFrequencyBand",
            "SupportedFrequencyBands": "SupportedFrequencyBands",
            "AssociatedDevice": [
                "url": "AssociatedDevice.",
                "node": ["MAC": "AssociatedDeviceMACAddress"]
            ]
        ])

        var wifiMacs = Set<String>()
        var wifiBand: [String: String] = [:]

        // 每个 WLAN 实例先算出频段，再把它名下的终端打上标签
        for wl in wifiRows {
            let band = bandOf(wl)
            guard let ads = wl["AssociatedDevice"] as? [[String: Any]] else { continue }
            for ad in ads {
                let m = (ad["MAC"] as? String ?? "").uppercased()
                guard !m.isEmpty else { continue }
                wifiMacs.insert(m)
                if !band.isEmpty { wifiBand[m] = band }
            }
        }

        // 单个 WLAN 实例的频段判定：SSID 对照 → 频率字段 → 信道
        func bandOf(_ wl: [String: Any]) -> String {
            let ssid = (wl["SSID"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let s24 = status["ssid24"].trimmingCharacters(in: .whitespaces)
            let s5 = status["ssid5g"].trimmingCharacters(in: .whitespaces)

            if !ssid.isEmpty {
                if !s5.isEmpty, ssid.caseInsensitiveCompare(s5) == .orderedSame { return "5G Wi-Fi" }
                if !s24.isEmpty, ssid.caseInsensitiveCompare(s24) == .orderedSame { return "2.4G Wi-Fi" }
                // SSID 里带 5G 字样
                if ssid.uppercased().contains("5G") { return "5G Wi-Fi" }
                if ssid.uppercased().contains("2.4G") || ssid.uppercased().contains("2G") { return "2.4G Wi-Fi" }
            }
            for k in ["OperatingFrequencyBand", "SupportedFrequencyBands", "FrequencyBand"] {
                if let v = wl[k] as? String, !v.isEmpty {
                    return v.contains("5") ? "5G Wi-Fi" : "2.4G Wi-Fi"
                }
            }
            // 信道推断：2.4G 用 1-14，5G 从 32 起
            if let c = wl["Channel"] as? String, let ch = Int(c) {
                return ch <= 14 ? "2.4G Wi-Fi" : "5G Wi-Fi"
            } else if let ch = wl["Channel"] as? Int {
                return ch <= 14 ? "2.4G Wi-Fi" : "5G Wi-Fi"
            }
            return ""
        }

        // 2. Hosts 表（名称 / IP / 限速）
        let hostRows = await q("LANDevice.1.Hosts.Host.", [
            "HostName": "HostName",
            "MACAddress": "MACAddress",
            "IPAddress": "IPAddress",
            "Layer2Interface": "Layer2Interface",
            "MaxDSBandwidth": "MaxDSBandwidth",
            "MaxUSBandwidth": "MaxUSBandwidth"
        ])

        var result: [CpeHost] = []
        var seen = Set<String>()

        for r in hostRows {
            let mac = (r["MACAddress"] as? String ?? "").uppercased()
            guard !mac.isEmpty, !seen.contains(mac) else { continue }

            let ip = (r["IPAddress"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let layer = (r["Layer2Interface"] as? String ?? "").uppercased()
            // 判定顺序：WiFi 关联表最可靠 → 接口名 → 兜底
            let inWifiTable = wifiMacs.contains(mac)
            let layerSaysEth = layer.contains("ETHERNET") || layer.contains("LANETH")
            let layerSaysWifi = layer.contains("WLAN") || layer.contains("WIFI")
                || layer.contains("802.11")

            // 不在 WiFi 表里、又不是明确的无线接口 → 按有线处理
            let isWired = !inWifiTable && (layerSaysEth || (!layerSaysWifi && !ip.isEmpty))

            // 在线判定：有 IP，或出现在 WiFi 关联表里
            let online = !ip.isEmpty || inWifiTable
            guard online else { continue }

            let name = (r["HostName"] as? String) ?? "设备"
            var display = name
            if name.isEmpty || name == "unknown" {
                display = inWifiTable ? "移动设备" : "有线设备"
            }

            seen.insert(mac)
            result.append(CpeHost(
                idx: String(r["child_node_idx"] as? Int ?? 0),
                name: display,
                mac: mac,
                ip: ip,
                iface: isWired ? "Ethernet" : (wifiBand[mac] ?? "Wi-Fi"),
                downLimit: (r["MaxDSBandwidth"] as? String) ?? "0",
                upLimit: (r["MaxUSBandwidth"] as? String) ?? "0"))
        }

        // 3. 补充 WiFi 在线但 Hosts 表没有的
        for mac in wifiMacs where !seen.contains(mac) {
            result.append(CpeHost(idx: "", name: "移动设备", mac: mac, ip: "",
                                  iface: wifiBand[mac] ?? "Wi-Fi",
                                  downLimit: "0", upLimit: "0"))
        }

        // 4. 排序：有线优先，其次 5G，最后 2.4G
        result.sort { a, b in
            let pa = a.isWired ? 0 : (a.bandLabel.contains("5G") ? 1 : 2)
            let pb = b.isWired ? 0 : (b.bandLabel.contains("5G") ? 1 : 2)
            return pa < pb
        }

        hosts = result
    }

    func fetchSms() async -> [CpeSms] {
        // 不同固件的短信节点路径不一样，逐个试，取第一个有数据的
        let urls = [
            "X_FH_MobileNetwork.SMS_Recv.SMS_RecvMsg.",
            "X_FH_MobileNetwork.SMS.SMS_RecvMsg.",
            "X_FH_SMS.SMS_RecvMsg.",
            "X_FH_MobileNetwork.SMS_Recv.",
            "InternetGatewayDevice.X_FH_MobileNetwork.SMS_Recv.SMS_RecvMsg."
        ]

        for url in urls {
            let rows = await mp("get_xml_childnode_value", [
                "data_1": [
                    "url": url,
                    "node": [
                        "Sender": "Sender",
                        "Phone": "Phone",
                        "SmsSender": "SmsSender",
                        "Content": "Content",
                        "SmsContent": "SmsContent",
                        "RecvTime": "RecvTime",
                        "Date": "Date"
                    ]
                ]
            ])
            let list = rows.compactMap { row -> CpeSms? in
                let sender = firstString(row, ["Sender", "Phone", "SmsSender"])
                let content = firstString(row, ["Content", "SmsContent"])
                guard !sender.isEmpty || !content.isEmpty else { return nil }
                return CpeSms(sender: sender, content: content,
                              time: firstString(row, ["RecvTime", "Date"]))
            }
            if !list.isEmpty { return list }
        }
        return []
    }

    private func firstString(_ row: [String: Any], _ keys: [String]) -> String {
        for k in keys {
            if let v = row[k] as? String {
                let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty && t != "-" { return t }
            }
        }
        return ""
    }

    // MARK: - 控制

    func setToggle(node: String, on: Bool) async -> Bool {
        let ok = await set1(node, on ? "1" : "0")
        if ok { await fetchStatus() }
        return ok
    }

    // MARK: - 网络切换监听

    private var watchTask: Task<Void, Never>?
    private var offlineStreak = 0

    /// 开始监听：每 12 秒确认当前设备是否还在，以及是否切到了别的设备
    func startWatching() {
        watchTask?.cancel()
        offlineStreak = 0
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.checkDeviceChange()
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        detectedProfile = nil
        currentOffline = false
        offlineStreak = 0
    }

    private func checkDeviceChange() async {
        guard isLoggedIn, let cur = activeProfile else { return }
        guard !cur.host.isEmpty else { return }

        // 当前设备还在？
        if await CpeDetector.reachable(cur.host) {
            offlineStreak = 0
            if currentOffline { currentOffline = false }
            NotifySwitch.lastOfflineNotify = ""     // 恢复后允许再次提醒
            return
        }

        offlineStreak += 1
        guard offlineStreak >= 2 else { return }   // 连续 2 次（约 24 秒）才认定断开
        currentOffline = true

        // 断开提醒（每台设备只提醒一次）
        if NotifySwitch.offline, NotifySwitch.lastOfflineNotify != cur.host {
            NotifySwitch.lastOfflineNotify = cur.host
            NotifyCenter.shared.post(
                title: "设备已断开",
                body: cur.displayTitle + " · " + cur.host + " 连不上了",
                category: "CAT_OFFLINE",
                userInfo: ["host": cur.host])
        }

        // 找其它已保存的设备
        for p in ProfileStore.loadAll() where p.id != cur.id && !p.host.isEmpty {
            if await CpeDetector.reachable(p.host) {
                if detectedProfile?.id != p.id {
                    detectedProfile = p
                    toast("检测到 \(p.displayTitle)，是否切换？", kind: .info)
                    if NotifySwitch.deviceSwitch, NotifySwitch.lastSwitchNotify != p.host {
                        NotifySwitch.lastSwitchNotify = p.host
                        NotifyCenter.shared.post(
                            title: "检测到另一台设备",
                            body: p.displayTitle + " · " + p.host,
                            category: "CAT_SWITCH",
                            userInfo: ["host": p.host])
                    }
                }
                return
            }
        }
    }

    /// 手动切到检测到的设备
    func switchTo(_ p: CpeProfile) async {
        detectedProfile = nil
        offlineStreak = 0
        currentOffline = false
        stopPolling()
        let ok = await login(profile: p)
        if ok {
            ProfileStore.activeID = p.id
            startPolling()
            startWatching()
            toast("已切换到 " + p.displayTitle, kind: .success)
        } else {
            toast(errorText ?? "切换失败", kind: .error)
        }
    }

    func dismissDetected() {
        detectedProfile = nil
    }

    /// 重启设备：按厂商分流
    func reboot() async -> Bool {
        if isHuawei { return await HuaweiAPI.shared.reboot() }
        if isOppo {
            return await OppoBridge.shared.reboot()
        }

        // 烽火：优先原生 API，失败再走 WebView 桥
        if useNative {
            do {
                try await CpeNativeAPI.shared.runCommand("REBOOT_WEB")
                return true
            } catch {
                diagLog += "原生重启失败，尝试桥接…\n"
            }
        }
        if bridge.ready {
            return await bridge.runCommand("REBOOT_WEB")
        }
        diagLog += "烽火未连接，无法重启\n"
        return false
    }

    /// 频段锁定
    func applyBandLock(enable: Bool, nr: [Int], lte: [Int]) async -> Bool {
        let ns = CpeNode.netSet
        var ok = await set1(ns + "LockBandEnable", enable ? "1" : "0")
        if !nr.isEmpty {
            ok = await set1(ns + "NRLockBAND", nr.map(String.init).joined(separator: ",")) && ok
        }
        if !lte.isEmpty {
            ok = await set1(ns + "LTELockBAND", lte.map(String.init).joined(separator: ",")) && ok
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await fetchStatus()
        return ok
    }

    /// 运营商锁定
    func applyCarrierLock(enable: Bool, serial: String) async -> Bool {
        let ns = CpeNode.netSet
        var ok = await set1(ns + "CarrierLockEnable", enable ? "1" : "0")
        if !serial.isEmpty {
            ok = await set1(ns + "CarrierSerialNum", serial) && ok
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await fetchStatus()
        return ok
    }

    /// 重命名设备
    func renameHost(idx: String, name: String) async -> Bool {
        await set1("LANDevice.1.Hosts.Host.\(idx).X_FH_DevName", name)
    }

    /// 限速（Mbps → Kbps）
    func limitHost(idx: String, down: String, up: String) async -> Bool {
        let base = "LANDevice.1.Hosts.Host.\(idx)."
        let dK = String(Int((Double(down) ?? 0) * 1024))
        let uK = String(Int((Double(up) ?? 0) * 1024))
        let ok1 = await set1(base + "MaxDSBandwidth", dK)
        let ok2 = await set1(base + "MaxUSBandwidth", uK)
        return ok1 && ok2
    }

    /// 发送短信
    func sendSms(to: String, text: String) async -> Bool {
        guard !to.trimmingCharacters(in: .whitespaces).isEmpty,
              !text.isEmpty else { return false }
        let rows = await mp("send_sms", ["phone_number": to, "content": text])

        // 有返回时检查错误码；为空则按成功处理（多数固件成功时不返回内容）
        if let first = rows.first {
            for k in ["ErrorCode", "errorcode", "code"] {
                if let v = first[k] as? String, v != "0" && !v.isEmpty { return false }
                if let v = first[k] as? Int, v != 0 { return false }
            }
        }
        return true
    }

    // MARK: - 轮询

    /// 启动轮询。force=false 时若已在运行则跳过（避免 scenePhase 与 onAppear 重复启动）
    func startPolling(force: Bool = true) {
        if !force, pollTask != nil, !(pollTask?.isCancelled ?? true) { return }
        stopPolling()
        startWatching()
        lastTick = Date()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.fetchStatus()
                self.lastTick = Date()
                let ns = UInt64(max(0.5, self.refreshInterval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
        }
    }

    /// 自愈：超过 3 倍间隔无心跳说明轮询被系统挂起，重启它
    func ensurePollingAlive() {
        guard isLoggedIn else { return }
        if Date().timeIntervalSince(lastTick) > max(3.0, refreshInterval * 3) {
            startPolling(force: true)
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// 完全断开（退出登录/切设备时用）
    func teardown() {
        stopPolling()
        stopWatching()
    }

    /// 从后台回到前台：重建会话并立即刷新
    /// 后台释放会话（仅烽火，用于腾出设备在线名额）
    func releaseSessionForBackground() {
        guard isFiberHome else { return }
        stopPolling()
        FiberExtras.sessionReleased = true
        // 尽力通知设备登出（失败也不影响本地状态）
        Task { try? await CpeNativeAPI.shared.logout() }
    }

    func resumeFromBackground() async {
        guard isLoggedIn else { return }

        // 之前后台释放过会话 → 重新登录
        if FiberExtras.sessionReleased {
            FiberExtras.sessionReleased = false
            if isHuawei {
                let cfg = Settings.load()
                _ = try? await HuaweiAPI.shared.login(host: cfg.host, user: cfg.user, password: cfg.password)
            } else if !isOppo, Settings.load().isConfigured {
                let cfg = Settings.load()
                CpeNativeAPI.shared.configure(host: cfg.host, user: cfg.user, pass: cfg.password)
                _ = try? await CpeNativeAPI.shared.login()
            }
        }
        // 会话可能已失效，重新登录
        let cfg = Settings.load()
        if cfg.isConfigured {
            CpeNativeAPI.shared.configure(host: cfg.host, user: cfg.user, pass: cfg.password)
            _ = try? await CpeNativeAPI.shared.login()
            useNative = true
        }
        await fetchAll()
        startPolling(force: false)
    }

    /// 当前是否有轮询在跑
    var isPolling: Bool { pollTask != nil && !(pollTask?.isCancelled ?? true) }
}
