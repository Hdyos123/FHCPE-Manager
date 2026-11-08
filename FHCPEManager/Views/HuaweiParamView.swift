import SwiftUI

/// 华为参数页：设备头卡 + 蜂窝网络 + SIM 与身份 + WAN 与地址 + 固件与档案 + 进网标志
struct HuaweiParamView: View {
    @EnvironmentObject var store: CpeStore

    @State private var revealed: Set<String> = []
    @State private var showModulation = false
    @State private var showHardware = false

    private var s: CpeStatus { store.status }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                deviceHeader
                cellularCard
                identityCard
                wanCard
                firmwareCard
                certCard
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 96)
        }
        .background(GlassListBackground())
        .refreshable { await store.fetchAll() }
        .sheet(isPresented: $showModulation) {
            ModulationSheet(status: s)
        }
        .sheet(isPresented: $showHardware) {
            HardwareSheet(status: s)
        }
    }
}

// MARK: - 设备头卡
private extension HuaweiParamView {
    var deviceHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                Text("设备")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
                Spacer()
            }

            Text(s["model"].isEmpty ? "H153-381" : s["model"])
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.primary)

            Text("已连接 · 已在线 \(uptimeText)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20)
    }

    var uptimeText: String {
        let up = Int(s["uptime"]) ?? 0
        guard up > 0 else { return "--" }
        let d = up / 86400, h = (up % 86400) / 3600
        return "\(d)天\(h)时"
    }
}

// MARK: - 蜂窝网络
private extension HuaweiParamView {
    var cellularCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("蜂窝网络")

            kv("Band", s["bandFull"].isEmpty ? (s["band"].isEmpty ? "--" : s["band"]) : s["bandFull"])
            Divider().opacity(0.25).padding(.leading, 16)
            kv("PLMN", s["plmn"].isEmpty ? "--" : s["plmn"])
            Divider().opacity(0.25).padding(.leading, 16)

            HStack {
                Text("CELL_ID")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(s["cellid"].isEmpty ? "--" : s["cellid"])
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(.primary)
                Button {
                    Haptic.success()
                    UIPasteboard.general.string = s["cellid"]
                    store.toast("已复制 CELL_ID")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider().opacity(0.25).padding(.leading, 16)

            Button {
                Haptic.light()
                showModulation = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color.purple.opacity(0.16)).frame(width: 28, height: 28)
                        Image(systemName: "waveform")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.purple)
                    }
                    Text("调制与码流")
                        .font(.system(size: 13.5))
                    Spacer()
                    Text("CQI0:\(s["qci"].isEmpty ? "--" : s["qci"])")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .glassCard(radius: 20)
    }

    func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 16, weight: .bold))
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
    }

    func kv(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Spacer()
            Text(v)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: - SIM 与身份（打码 + 眼睛）
private extension HuaweiParamView {
    var identityCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("SIM 与身份")
            secretRow("序列号", key: "sn", value: s["sn"])
            Divider().opacity(0.25).padding(.leading, 16)
            secretRow("IMEI", key: "imei", value: s["imei"])
            Divider().opacity(0.25).padding(.leading, 16)
            secretRow("IMSI", key: "imsi", value: s["imsi"])
            Divider().opacity(0.25).padding(.leading, 16)
            secretRow("本机号码", key: "phone", value: phoneText)
        }
        .glassCard(radius: 20)
    }

    var phoneText: String {
        let p = s["phone"]
        return p.isEmpty ? "--" : p
    }

    func secretRow(_ label: String, key: String, value: String) -> some View {
        let on = revealed.contains(key)
        return HStack {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty || value == "--" ? "--" : (on ? value : mask(value)))
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Button {
                Haptic.light()
                if on { revealed.remove(key) } else { revealed.insert(key) }
            } label: {
                Image(systemName: on ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// 前3 + 点 + 后3
    func mask(_ v: String) -> String {
        guard v.count > 6 else { return v }
        let head = String(v.prefix(3))
        let tail = String(v.suffix(3))
        return head + String(repeating: "·", count: min(9, max(3, v.count - 6))) + tail
    }
}

// MARK: - WAN 与地址
private extension HuaweiParamView {
    var wanCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("WAN 与地址")
            copyRow("LAN MAC 地址", value: s["mac"])
            Divider().opacity(0.25).padding(.leading, 16)
            copyRow("流量 WAN IP 地址", value: s["wanIP"])
            Divider().opacity(0.25).padding(.leading, 16)
            copyRow("流量 WAN IPv6 地址", value: s["wanIPv6"], multiline: true)
            Divider().opacity(0.25).padding(.leading, 16)
            copyRow("宽带 WAN IP 地址", value: "未知")
            Divider().opacity(0.25).padding(.leading, 16)
            copyRow("宽带 WAN IPv6 地址", value: "未知")
        }
        .glassCard(radius: 20)
    }

    func copyRow(_ label: String, value: String, multiline: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value.isEmpty ? "未知" : value)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(value.isEmpty ? Color.secondary : Color.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(multiline ? 2 : 1)
            if !value.isEmpty {
                Button {
                    Haptic.success()
                    UIPasteboard.general.string = value
                    store.toast("已复制")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: - 固件与档案
private extension HuaweiParamView {
    var firmwareCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("固件与档案")

            HStack {
                Text("软件版本号")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(s["swver"].isEmpty ? "--" : s["swver"])
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Button {
                    Haptic.success()
                    UIPasteboard.general.string = s["swver"]
                    store.toast("已复制")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider().opacity(0.25).padding(.leading, 16)

            Button {
                Haptic.light()
                showHardware = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color.blue.opacity(0.14)).frame(width: 28, height: 28)
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    Text("版本档案")
                        .font(.system(size: 13.5))
                    Spacer()
                    Text(s["hwver"].isEmpty ? "--" : s["hwver"])
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .glassCard(radius: 20)
    }
}

// MARK: - 进网标志
private extension HuaweiParamView {
    var certCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("进网标志")

            HStack {
                Text("进网标志代码")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(certCode)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(.primary)
                Button {
                    Haptic.success()
                    UIPasteboard.general.string = certCode
                    store.toast("已复制进网标志")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Button {
                Haptic.light()
                if let u = URL(string: "https://jwxk.miit.gov.cn/") {
                    UIApplication.shared.open(u)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 12))
                    Text("到工信部核验真伪")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.10))
                )
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
            .buttonStyle(.plain)
        }
        .glassCard(radius: 20)
    }

    var certCode: String {
        let c = s["certcode"]
        return c.isEmpty ? "--" : c
    }
}

// MARK: - 调制与码流
struct ModulationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let status: CpeStatus

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    row("上行 MCS", status["ulmcs"])
                    row("下行 MCS", status["dlmcs"])
                    row("CQI0", status["qci"])
                    row("Rank / 层数", status["rank"])
                    row("BLER", status["bler"])
                    row("发射功率", status["txpower"])
                }
                .padding(14)
            }
            .background(GlassListBackground())
            .navigationTitle("调制与码流")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Text(v.isEmpty ? "--" : v)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 14)
    }
}

// MARK: - 版本档案
struct HardwareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let status: CpeStatus

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    row("硬件版本", status["hwver"])
                    row("软件版本", status["swver"])
                    row("网页版本", status["webver"])
                    row("设备型号", status["model"])
                    row("序列号", status["sn"])
                }
                .padding(14)
            }
            .background(GlassListBackground())
            .navigationTitle("版本档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(v.isEmpty ? "--" : v)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 14)
    }
}
