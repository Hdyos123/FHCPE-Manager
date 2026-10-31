import Foundation

/// 把 OPPO 的原始键值映射成与烽火一致的字段名，
/// 这样首页 UI 不需要区分厂商就能直接显示。
extension OppoParser {

    /// 原始解析结果 → 统一的 CpeStatus.raw 结构
    static func normalize(_ raw: [String: String]) -> [String: String] {
        var v = raw

        // 运营商
        switch raw["plmn"] {
        case "46001": v["carrier"] = "UNICOM"
        case "46000": v["carrier"] = "CMCC"
        case "46011": v["carrier"] = "CT"
        default: break
        }

        // 网络制式：5G → "3"，4G → "2"
        let mode = raw["netmode"] ?? ""
        if mode.contains("5G") { v["netmode"] = "3" }
        else if mode.contains("4G") { v["netmode"] = "2" }

        // 在线判断：拿到 PCI 就算在线
        let hasCell = !(raw["pci"] ?? "").isEmpty
        v["regstatus"] = hasCell ? "0" : "1"
        v["simstatus"] = hasCell ? "0" : "1"

        // 频段：n78 → 78，B3 → 3
        if let b = raw["band"] {
            let digits = b.replacingOccurrences(of: "n", with: "")
                           .replacingOccurrences(of: "N", with: "")
                           .replacingOccurrences(of: "B", with: "")
            v["band"] = digits
        }

        // 带宽 OPPO 首页不显示，留空由 UI 处理
        v["bw"] = ""

        // 速率：转成 bit/s，与烽火的 speedRx/speedTx 语义一致
        if let s = raw["speedRx"] {
            v["speedRx"] = String(Int(toMbps(s) * 1_000_000 / 8))
        }
        if let s = raw["speedTx"] {
            v["speedTx"] = String(Int(toMbps(s) * 1_000_000 / 8))
        }

        // 流量：OPPO 的 Total/Upload/Download 是 GB/MB 字符串，转成字节数
        if let up = raw["trafficUp"] {
            v["monthTx"] = String(Int(parseBytes(up)))
        }
        if let down = raw["trafficDown"] {
            v["monthRx"] = String(Int(parseBytes(down)))
        }
        if let total = raw["total"] {
            let bytes = parseBytes(total)
            v["monthTotal"] = String(Int(bytes))
            // OPPO 无「今日」数据，用本月值兜底避免显示空
            v["todayTotal"] = String(Int(bytes))
        }

        // CPU / 内存
        if let c = raw["cpu"] { v["cpu"] = c }
        if let m = raw["mem"] {
            // 转成 memFree/memTotal 形式（按 100 为总量估算）
            v["memTotal"] = "100"
            v["memFree"] = String(max(0, 100 - (Int(m) ?? 0)))
        }

        // 运行时长："0day(s) 01:32:26" → 秒
        if let u = raw["uptime"] {
            v["uptime"] = String(parseUptime(u))
        }

        // 在线设备数（OPPO 在「There are total of N devices」里）
        if let t = raw["deviceCount"] { v["online"] = t }

        // OPPO 不提供的字段：置空，UI 会显示 --
        for k in ["qci", "dlmax", "ulmax", "arfcn", "rssi", "tempRaw", "sn24"] {
            if v[k] == nil { v[k] = "" }
        }

        return v
    }

    /// "50.39 GB" / "834.07 MB" → 字节数
    static func parseBytes(_ s: String) -> Double {
        let t = s.uppercased().trimmingCharacters(in: .whitespaces)
        var mult: Double = 1
        var numStr = t
        if t.hasSuffix("TB") { mult = 1024 * 1024 * 1024 * 1024; numStr = String(t.dropLast(2)) }
        else if t.hasSuffix("GB") { mult = 1024 * 1024 * 1024; numStr = String(t.dropLast(2)) }
        else if t.hasSuffix("MB") { mult = 1024 * 1024; numStr = String(t.dropLast(2)) }
        else if t.hasSuffix("KB") { mult = 1024; numStr = String(t.dropLast(2)) }
        else if t.hasSuffix("B") { numStr = String(t.dropLast(1)) }
        let n = Double(numStr.trimmingCharacters(in: .whitespaces)) ?? 0
        return n * mult
    }

    /// "0day(s) 01:32:26" → 秒
    static func parseUptime(_ s: String) -> Int {
        var days = 0
        var rest = s
        if let r = s.range(of: "day(s)") {
            let d = s[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            days = Int(d) ?? 0
            rest = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        let parts = rest.split(separator: ":").compactMap { Int($0) }
        var sec = days * 86400
        if parts.count == 3 { sec += parts[0]*3600 + parts[1]*60 + parts[2] }
        else if parts.count == 2 { sec += parts[0]*60 + parts[1] }
        return sec
    }

    /// 从整页文本里抽出在线设备数
    static func extractDeviceCount(_ text: String) -> String? {
        // 匹配 "There are total of 2 devices"
        guard let r = text.range(of: "total of ") else { return nil }
        let tail = text[r.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }
}
