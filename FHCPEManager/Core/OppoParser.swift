import Foundation

/// 解析 OPPO CPE 首页文本
///
/// OPPO 首页是「标签\n值」成对出现的纯文本，直接按行扫描。
enum OppoParser {

    static func parse(_ text: String) -> [String: String] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var out: [String: String] = [:]

        /// 找某个标签后面的值
        func after(_ label: String) -> String? {
            guard let i = lines.firstIndex(of: label), i + 1 < lines.count else { return nil }
            return lines[i + 1]
        }

        // 速率（单位已在值里，如 "10.34 Mbps"）
        if let v = after("UL Data Rate") { out["speedTx"] = v }
        if let v = after("DL Data Rate") { out["speedRx"] = v }

        // 信号
        if let v = after("RSRP") { out["rsrp"] = v.replacingOccurrences(of: "dBm", with: "") }
        if let v = after("RSRQ") { out["rsrq"] = v.replacingOccurrences(of: "dB", with: "") }
        if let v = after("SINR") { out["sinr"] = v.replacingOccurrences(of: "dB", with: "") }
        if let v = after("RSSI") { out["rssi"] = v.replacingOccurrences(of: "dBm", with: "") }

        // 小区
        if let v = after("PCI") { out["pci"] = v }
        if let v = after("Frequency Band") { out["band"] = v }
        if let v = after("PLMN") { out["plmn"] = v }
        if let v = after("Carrier Aggregation") { out["ca"] = v }
        if let v = after("Network Status") { out["netmode"] = v }

        // 流量（单位 GB / MB，保留原样）
        if let v = after("Total") { out["total"] = v }
        if let v = after("Upload") { out["trafficUp"] = v }
        if let v = after("Download") { out["trafficDown"] = v }

        // 设备
        if let v = after("Device Name") { out["model"] = v }
        if let v = after("Serial Number") { out["sn"] = v }
        if let v = after("Software Version") { out["swver"] = v }
        if let v = after("Hardware Version") { out["hwver"] = v }
        if let v = after("Manufacturer Info") { out["vendor"] = v }
        if let v = after("System Uptime") { out["uptime"] = v }

        // 系统
        if let v = after("CPU Usage") { out["cpu"] = v.replacingOccurrences(of: "%", with: "") }
        if let v = after("Memory Usage") { out["mem"] = v.replacingOccurrences(of: "%", with: "") }
        if let v = after("Cellular Network WAN IPv4 Address") { out["wanIP"] = v }

        // SSID
        if let v = after("SSID 2.4 GHz") { out["ssid24"] = v }
        if let v = after("SSID 5 GHz") { out["ssid5g"] = v }

        return out
    }

    /// 直接从「标签→值」字典解析（由 JS 侧预提取，避免传输整页文本）
    static func parseFromPairs(_ d: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        func g(_ k: String) -> String? { d[k] }

        if let v = g("UL Data Rate") { out["speedTx"] = v }
        if let v = g("DL Data Rate") { out["speedRx"] = v }
        if let v = g("RSRP") { out["rsrp"] = v.replacingOccurrences(of: "dBm", with: "") }
        if let v = g("RSRQ") { out["rsrq"] = v.replacingOccurrences(of: "dB", with: "") }
        if let v = g("SINR") { out["sinr"] = v.replacingOccurrences(of: "dB", with: "") }
        if let v = g("RSSI") { out["rssi"] = v.replacingOccurrences(of: "dBm", with: "") }
        if let v = g("PCI") { out["pci"] = v }
        if let v = g("Frequency Band") { out["band"] = v }
        if let v = g("PLMN") { out["plmn"] = v }
        if let v = g("Carrier Aggregation") { out["ca"] = v }
        if let v = g("Network Status") { out["netmode"] = v }
        if let v = g("Total") { out["total"] = v }
        if let v = g("Upload") { out["trafficUp"] = v }
        if let v = g("Download") { out["trafficDown"] = v }
        if let v = g("Device Name") { out["model"] = v }
        if let v = g("Serial Number") { out["sn"] = v }
        if let v = g("Software Version") { out["swver"] = v }
        if let v = g("Hardware Version") { out["hwver"] = v }
        if let v = g("Manufacturer Info") { out["vendor"] = v }
        if let v = g("System Uptime") { out["uptime"] = v }
        if let v = g("CPU Usage") { out["cpu"] = v.replacingOccurrences(of: "%", with: "") }
        if let v = g("Memory Usage") { out["mem"] = v.replacingOccurrences(of: "%", with: "") }
        if let v = g("SSID 2.4 GHz") { out["ssid24"] = v }
        if let v = g("SSID 5 GHz") { out["ssid5g"] = v }
        if let v = g("deviceCount") { out["deviceCount"] = v }
        return out
    }

    /// 把 "10.34 Mbps" / "536.61 Kbps" 转成 Mbps 数值
    static func toMbps(_ s: String) -> Double {
        let t = s.uppercased()
        if let n = Double(t.replacingOccurrences(of: "MBPS", with: "")
                           .replacingOccurrences(of: "KBPS", with: "")
                           .trimmingCharacters(in: .whitespaces)) {
            if t.contains("KBPS") { return n / 1000 }
            return n
        }
        return 0
    }
}
