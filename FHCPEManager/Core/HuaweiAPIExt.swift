import Foundation

// MARK: - 华为扩展接口（天线 / WLAN / VPN / MAC 过滤 / 加速 / 双宽带 / 终端选路）

extension HuaweiAPI {

    // MARK: 天线

    enum AntennaMode: Int, CaseIterable {
        case auto = 0, builtin = 1, external = 2, mixed = 3
        var title: String {
            switch self {
            case .auto:     return "自动"
            case .builtin:  return "内置"
            case .external: return "外置"
            case .mixed:    return "混合"
            }
        }
        var detail: String {
            switch self {
            case .auto:     return "由设备自己判断，插了外置天线就走外置。这是出厂默认档。"
            case .builtin:  return "强制走机内天线，接在机身上的外置天线会被忽略。"
            case .external: return "强制走外接天线接口，机身上没接天线的话信号会掉到很弱。"
            case .mixed:    return "两根天线各走各的。"
            }
        }
    }

    /// 读取天线设置；返回 nil 表示固件不支持
    func fetchAntenna() async -> (mode: Int, ant1: String, ant2: String)? {
        guard let n = try? await request("GET", "/api/device/antenna_type", body: nil) else { return nil }
        let mode = Int(n.text("antenna_set_type") ?? "0") ?? 0
        return (mode,
                n.text("antenna_type_1") ?? "-",
                n.text("antenna_type_2") ?? "-")
    }

    func setAntenna(_ mode: AntennaMode) async -> Bool {
        do {
            _ = try await request("POST", "/api/device/antenna_set_type",
                                  body: "<request><antenna_set_type>\(mode.rawValue)</antenna_set_type></request>")
            return true
        } catch {
            lastErrorText = msg(error)
            return false
        }
    }

    // MARK: WLAN 高级

    struct WlanBand {
        var index: Int          // 1 = 2.4G, 2 = 5G
        var ssid: String
        var channel: String
        var bandwidth: String
        var power: String       // 0 省电 / 1 标准 / 2 穿墙
        var country: String
        var ssidEnable: Bool
    }

    func fetchWlan() async -> [WlanBand] {
        guard let n = try? await request("GET", "/api/wlan/multi-basic-settings", body: nil) else { return [] }
        return n.all("Wlan").map { w in
            WlanBand(index: Int(w.text("Index") ?? "1") ?? 1,
                     ssid: w.text("Ssid") ?? "",
                     channel: w.text("Channel") ?? "0",
                     bandwidth: w.text("Bandwidth") ?? "20",
                     power: w.text("WifiTxPower") ?? "1",
                     country: w.text("CountryCode") ?? "",
                     ssidEnable: (w.text("WifiEnable") ?? "1") == "1")
        }
    }

    func setWlan(_ w: WlanBand) async -> Bool {
        let body = """
        <request><Wlan><Index>\(w.index)</Index><WifiEnable>\(w.ssidEnable ? 1 : 0)</WifiEnable>\
        <Ssid>\(Self.escape(w.ssid))</Ssid><Channel>\(w.channel)</Channel>\
        <Bandwidth>\(w.bandwidth)</Bandwidth><WifiTxPower>\(w.power)</WifiTxPower>\
        <CountryCode>\(w.country)</CountryCode></Wlan></request>
        """
        do {
            _ = try await request("POST", "/api/wlan/multi-basic-settings", body: body)
            return true
        } catch {
            lastErrorText = msg(error)
            return false
        }
    }

    // MARK: MAC 过滤

    struct MacFilterState {
        var enabled: Bool
        var policy: Int         // 0 黑名单 / 1 白名单
        var hosts: [(name: String, mac: String)]
    }

    func fetchMacFilter() async -> MacFilterState? {
        guard let n = try? await request("GET", "/api/wlan/multi-macfilter-settings", body: nil) else { return nil }
        let hosts = n.all("Host").map { h in
            (name: h.text("HostName") ?? "-", mac: h.text("MacAddress") ?? "-")
        }
        return MacFilterState(enabled: (n.text("MacFilterPolicy") ?? "0") == "1" || (n.text("MacFilterMode") ?? "") != "",
                              policy: Int(n.text("MacFilterPolicy") ?? "0") ?? 0,
                              hosts: hosts)
    }

    /// 黑白名单：policy 0=黑名单 1=白名单
    func setMacFilter(enabled: Bool, policy: Int, macs: [String]) async -> Bool {
        let hostXml = macs.map { "<Host><MacAddress>\($0)</MacAddress></Host>" }.joined()
        let body = """
        <request><MacFilterPolicy>\(policy)</MacFilterPolicy>\
        <MacFilterMode>\(enabled ? "1" : "0")</MacFilterMode>\
        <Hosts>\(hostXml)</Hosts></request>
        """
        do {
            _ = try await request("POST", "/api/wlan/multi-macfilter-settings", body: body)
            return true
        } catch {
            lastErrorText = msg(error)
            return false
        }
    }

    // MARK: VPN

    struct VpnProfile {
        var kind: String        // ipsec / l2tp / pptp
        var name: String
        var server: String
        var user: String
        var tunnelPwd: String
    }

    func fetchVpn(_ kind: String) async -> [VpnProfile] {
        let path: String
        switch kind {
        case "l2tp": path = "/api/vpn/l2tp_settings"
        case "pptp": path = "/api/vpn/pptp_settings"
        default:     path = "/api/vpn/ipsec_settings"
        }
        guard let n = try? await request("GET", path, body: nil) else { return [] }
        return n.all("Connection").map { c in
            VpnProfile(kind: kind,
                       name: c.text("Name") ?? "-",
                       server: c.text("Server") ?? "",
                       user: c.text("Username") ?? "",
                       tunnelPwd: "")
        }
    }

    // MARK: 应用加速

    struct TurboState {
        var enabled: Bool
        var scene: Int          // 1 游戏 2 直播 3 会议
        var devices: [String]
    }

    func fetchTurbo() async -> TurboState? {
        guard let n = try? await request("GET", "/api/appturbo/control", body: nil) else { return nil }
        let devs = n.all("Device").map { $0.text("MacAddress") ?? "" }.filter { !$0.isEmpty }
        return TurboState(enabled: (n.text("Enable") ?? "0") == "1",
                          scene: Int(n.text("Scene") ?? "1") ?? 1,
                          devices: devs)
    }

    func setTurbo(enabled: Bool, scene: Int, devices: [String]) async -> Bool {
        let devXml = devices.map { "<Device><MacAddress>\($0)</MacAddress></Device>" }.joined()
        let body = """
        <request><Enable>\(enabled ? 1 : 0)</Enable><Scene>\(scene)</Scene>\
        <Devices>\(devXml)</Devices></request>
        """
        do {
            _ = try await request("POST", "/api/appturbo/control", body: body)
            return true
        } catch {
            lastErrorText = msg(error)
            return false
        }
    }

    // MARK: 双宽带 / 终端选路

    struct WanInfo {
        var ethernetUp: Bool
        var ethernetRate: String        // 协商速率
        var wanRateRx: Double           // 宽带实时下行（字节/秒）
        var wanRateTx: Double
        var defaultWan: String          // "ethernet" / "mobile"
    }

    func fetchWan() async -> WanInfo? {
        guard let n = try? await request("GET", "/api/ntwk/dualwaninfo", body: nil) else { return nil }
        let eth = n.find("Ethernet")
        let rate = (try? await request("GET", "/api/ntwk/ethwanrate", body: nil))
        return WanInfo(ethernetUp: (eth?.text("LinkStatus") ?? "0") == "1",
                       ethernetRate: rate?.text("Rate") ?? "-",
                       wanRateRx: Double(eth?.text("RxRate") ?? "0") ?? 0,
                       wanRateTx: Double(eth?.text("TxRate") ?? "0") ?? 0,
                       defaultWan: n.text("DefaultWan") ?? "mobile")
    }

    /// 终端绑定：mac → "ethernet" / "mobile" / ""（自动）
    func fetchWanBind() async -> [String: String] {
        guard let n = try? await request("GET", "/api/ntwk/devicewanbind", body: nil) else { return [:] }
        var m: [String: String] = [:]
        for d in n.all("Device") {
            if let mac = d.text("MacAddress"), let w = d.text("Wan") {
                m[mac.uppercased()] = w
            }
        }
        return m
    }

    func setWanBind(mac: String, wan: String) async -> Bool {
        let body = "<request><MacAddress>\(mac)</MacAddress><Wan>\(wan)</Wan></request>"
        do {
            _ = try await request("POST", "/api/ntwk/devicewanbind", body: body)
            return true
        } catch {
            lastErrorText = msg(error)
            return false
        }
    }

    // MARK: 信号灯定时

    func setLedTiming(enable: Bool, start: String, end: String) async -> Bool {
        // 华为例行接口：ledbreathswitch 控制呼吸灯，appctrlled 控制定时灭灯
        let body = """
        <request><LedTimeEnable>\(enable ? 1 : 0)</LedTimeEnable>        <StartTime>\(start)</StartTime><EndTime>\(end)</EndTime></request>
        """
        do {
            _ = try await request("POST", "/api/led/ledtiming", body: body)
            return true
        } catch {
            // 部分固件走 breathledswitch
            do {
                _ = try await request("POST", "/api/led/breathledswitch",
                                      body: "<request><breathled>\(enable ? 1 : 0)</breathled></request>")
                return true
            } catch {
                lastErrorText = msg(error)
                return false
            }
        }
    }

    // MARK: 固件升级

    struct UpgradeState {
        var autoUpdate: Bool
        var silentUpdate: Bool
    }

    func fetchUpgrade() async -> UpgradeState? {
        guard let n = try? await request("GET", "/api/online-update/autoupdate-config", body: nil) else { return nil }
        let s = try? await request("GET", "/api/fota/GetSilenceUpgradeEnable", body: nil)
        return UpgradeState(autoUpdate: (n.text("AutoUpdate") ?? "0") == "1",
                            silentUpdate: (s?.text("SilenceUpgradeEnable") ?? "0") == "1")
    }

    func setUpgrade(auto: Bool, silent: Bool) async -> Bool {
        do {
            _ = try await request("POST", "/api/online-update/autoupdate-config",
                                  body: "<request><AutoUpdate>\(auto ? 1 : 0)</AutoUpdate></request>")
            _ = try await request("POST", "/api/fota/SetSilenceUpgradeEnable",
                                  body: "<request><SilenceUpgradeEnable>\(silent ? 1 : 0)</SilenceUpgradeEnable></request>")
            return true
        } catch {
            lastErrorText = msg(error)
            return false
        }
    }

    // MARK: 改密码

    func changePassword(current: String, new: String) async -> Bool {
        let body = """
        <request><CurrentPassword>\(Self.escape(current))</CurrentPassword>\
        <Password>\(Self.escape(new))</Password></request>
        """
        do {
            _ = try await request("POST", "/api/user/password", body: body)
            // 改完要用新密码重登
            password = new
            do { try await login(host: host, user: user, password: new) } catch { }
            return true
        } catch {
            lastErrorText = msg(error)
            return false
        }
    }

    // MARK: 网络制式

    struct NetModeInfo {
        var list: [(name: String, value: String)]
        var current: String
    }

    func fetchNetModeList() async -> NetModeInfo? {
        guard let n = try? await request("GET", "/api/net/net-mode-list", body: nil) else { return nil }
        let list = n.all("NetworkMode").map { m in
            (name: m.text("Name") ?? m.text("Index") ?? "-",
             value: m.text("Index") ?? "")
        }
        return NetModeInfo(list: list, current: "")
    }

    func setNetMode(_ value: String) async -> Bool {
        let body = "<request><NetworkMode>\(value)</NetworkMode><NetworkBand>3FFFFFFF</NetworkBand></request>"
        do {
            _ = try await request("POST", "/api/net/net-mode", body: body)
            return true
        } catch {
            lastErrorText = msg(error)
            return false
        }
    }

    // MARK: 工具

    func msg(_ e: Error) -> String {
        (e as? LocalizedError)?.errorDescription ?? "\(e)"
    }
}
