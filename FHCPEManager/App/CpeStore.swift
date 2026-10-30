import Foundation
import SwiftUI

@MainActor
final class CpeStore: ObservableObject {
    @Published var status = CpeStatus()
    @Published var hosts: [CpeHost] = []
    @Published var smsList: [CpeSms] = []
    @Published var isLoggedIn = false
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var lastUpdate = Date()

    @Published var realtimeRx: Double = 0
    @Published var realtimeTx: Double = 0

    @Published var refreshInterval: Double {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "cpe.rateMs") }
    }

    private let bridge = CpeBridge.shared
    private var pollTask: Task<Void, Never>?
    private var useNative = false
    @Published var diagLog = ""

    init() {
        let saved = UserDefaults.standard.double(forKey: "cpe.rateMs")
        refreshInterval = saved > 0 ? saved : 1.0
    }

    // MARK: - 登录

    func login(host: String, user: String, password: String) async -> Bool {
        errorText = nil
        diagLog = ""
        isLoading = true
        defer { isLoading = false }

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
            let probe = try await CpeNativeAPI.shared.values(CpeNode.overview)
            if !probe.isEmpty {
                useNative = true
                Settings(host: host, user: user, password: password).save()
                isLoggedIn = true
                await fetchAll()
                return true
            }
            diagLog = "原生登录成功但取不到数据"
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
        let cfg = Settings.load()
        guard cfg.isConfigured else { return }

        CpeNativeAPI.shared.configure(host: cfg.host, user: cfg.user, pass: cfg.password)
        if (try? await CpeNativeAPI.shared.login()) != nil,
           let probe = try? await CpeNativeAPI.shared.values(CpeNode.overview),
           !probe.isEmpty {
            useNative = true
            isLoggedIn = true
            await fetchAll()
            return
        }

        let ok = await bridge.login(host: cfg.host, user: cfg.user, password: cfg.password)
        if ok {
            let probe = await bridge.fetchValues(CpeNode.overview)
            if !probe.isEmpty {
                useNative = false
                isLoggedIn = true
                await fetchAll()
            }
        }
    }

    // MARK: - 数据

    func fetchAll() async {
        async let a: Void = fetchStatus()
        async let b: Void = fetchHosts()
        _ = await (a, b)
        lastUpdate = Date()
    }


    // MARK: - 统一数据入口（自动分流 WebView / 原生）

    private func mp(_ method: String, _ data: [String: Any]) async -> [[String: Any]] {
        if useNative {
            return (try? await CpeNativeAPI.shared.multipost(method: method, data: data)) ?? []
        }
        return await bridge.multipost(method: method, data: data)
    }

    private func set1(_ url: String, _ value: String) async -> Bool {
        if useNative {
            do { try await CpeNativeAPI.shared.setSingle(url: url, value: value); return true }
            catch { return false }
        }
        return await bridge.setSingle(url: url, value: value)
    }

    func fetchStatus() async {
        var v: [String: String] = [:]
        if useNative {
            v = (try? await CpeNativeAPI.shared.values(CpeNode.overview)) ?? [:]
        } else {
            v = await bridge.fetchValues(CpeNode.overview)
        }
        guard !v.isEmpty else { return }

        // uptime 不在 XML 节点里，需单独走 get_cmd_result_web
        let cmd = await mp("get_cmd_result_web", ["data_1": ["key": "UPTIME"]])
        if let first = cmd.first, let result = first["result"] as? String {
            v["uptime"] = result
        } else if let first = cmd.first, let num = first["result"] as? NSNumber {
            v["uptime"] = num.stringValue
        }

        status.raw = v
        realtimeRx = status.realtimeRx
        realtimeTx = status.realtimeTx
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
            "AssociatedDevice": [
                "url": "AssociatedDevice.",
                "node": ["MAC": "AssociatedDeviceMACAddress"]
            ]
        ])

        var wifiMacs = Set<String>()
        var wifiBand: [String: String] = [:]
        for (i, wl) in wifiRows.enumerated() {
            guard let ads = wl["AssociatedDevice"] as? [[String: Any]] else { continue }
            for ad in ads {
                let m = (ad["MAC"] as? String ?? "").uppercased()
                if !m.isEmpty {
                    wifiMacs.insert(m)
                    wifiBand[m] = i >= 4 ? "5G Wi-Fi" : "2.4G Wi-Fi"
                }
            }
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
            let isWired = layer.contains("LANETHERNET")
            let isWifi = layer.contains("WLANCONFIGURATION")

            // 在线判定：有 IP，或出现在 WiFi 关联表里
            let online = !ip.isEmpty || (isWifi && wifiMacs.contains(mac))
            guard online else { continue }

            let name = (r["HostName"] as? String) ?? "设备"
            var display = name
            if name.isEmpty || name == "unknown" {
                display = wifiMacs.contains(mac) ? "移动设备" : "有线设备"
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
        let rows = await mp("get_xml_childnode_value", [
            "data_1": [
                "url": "InternetGatewayDevice.X_FH_MobileNetwork.SMS_Recv.SMS_RecvMsg.",
                "node": ["Sender": "Sender", "Content": "Content", "RecvTime": "RecvTime"]
            ]
        ])
        return rows.compactMap { row -> CpeSms? in
            let sender = (row["Sender"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let content = (row["Content"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard !sender.isEmpty || !content.isEmpty else { return nil }
            return CpeSms(sender: sender, content: content,
                          time: row["RecvTime"] as? String ?? "")
        }
    }

    // MARK: - 控制

    func setToggle(node: String, on: Bool) async -> Bool {
        let ok = await set1(node, on ? "1" : "0")
        if ok { await fetchStatus() }
        return ok
    }

    func reboot() async -> Bool {
        if useNative {
            do { try await CpeNativeAPI.shared.runCommand("REBOOT_WEB"); return true }
            catch { return false }
        }
        return await bridge.runCommand("REBOOT_WEB")
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
        let rows = await mp("send_sms", ["phone_number": to, "content": text])
        _ = rows
        return true
    }

    // MARK: - 轮询

    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.fetchStatus()
                let ns = UInt64(max(0.3, self.refreshInterval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
