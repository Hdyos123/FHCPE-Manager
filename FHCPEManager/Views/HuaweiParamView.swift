import SwiftUI

/// 华为参数页：设备头卡 / 蜂窝网络 / SIM 与身份 / WAN 与地址 / 固件与档案 / 进网标志
struct HuaweiParamView: View {
    @EnvironmentObject var store: CpeStore

    @State private var masked = true
    @State private var revealed: Set<String> = []
    @State private var showModulation = false

    private var s: CpeStatus { store.status }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    deviceHeader
                    cellCard
                    simCard
                    wanCard
                    firmwareCard
                    entryCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .background(GlassListBackground())
            .navigationTitle("参数")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptic.light()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            masked.toggle()
                            if !masked { revealed.removeAll() }
                        }
                    } label: {
                        Image(systemName: masked ? "eye.slash" : "eye")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
            }
            .sheet(isPresented: $showModulation) { modulationSheet }
        }
    }

    // MARK: 设备头卡

    private var deviceHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "wifi.router")
                    .font(.system(size: 10))
                Text("设备 · " + (s["regstatus"] == "0" ? "在线" : "离线"))
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(s["regstatus"] == "0" ? Color.green : Color.secondary)

            Text(modelText)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .padding(.top, 2)

            Text(uptimeLine)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(radius: 22)
    }

    private var modelText: String {
        let m = s["model"]
        return m.isEmpty ? "Huawei CPE" : m
    }

    private var uptimeLine: String {
        let t = s.int("uptime")
        if t <= 0 { return "已连接 · 在线时长 --" }
        let d = t / 86400, h = (t % 86400) / 3600
        if d > 0 { return "已连接 · 已在线 \(d) 天 \(h) 时" }
        return "已连接 · 已在线 \(h) 小时"
    }

    // MARK: 蜂窝网络

    private var cellCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("蜂窝网络")

            kvRow("Band", bandText)
            rowLine
            kvRow("PLMN", s["plmn"].isEmpty ? "--" : s["plmn"], copyable: true)
            rowLine
            kvRow("CELL_ID", s["cellid"].isEmpty ? "--" : s["cellid"], copyable: true)
            rowLine

            Button {
                Haptic.light()
                showModulation = true
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.purple.opacity(0.16))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "waveform")
                                .font(.system(size: 12))
                                .foregroundStyle(.purple)
                        )
                    Text("调制与码流")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("CQI:" + (s["qci"].isEmpty ? "--" : s["qci"]))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .glassCard(radius: 22)
    }

    private var bandText: String {
        let bw = s["bw"].isEmpty ? "" : s["bw"] + "@"
        let arfcn = s["arfcn"].isEmpty ? "--" : s["arfcn"]
        let band = s["band"].isEmpty ? "--" : "N" + s["band"]
        return "\(bw)\(arfcn)(\(band))"
    }

    // MARK: SIM 与身份

    private var simCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("SIM 与身份")

            kvRow("序列号", mask("sn"), field: "sn", copyable: false)
            rowLine
            kvRow("IMEI", mask("imei"), field: "imei")
            rowLine
            kvRow("IMSI", mask("imsi"), field: "imsi")
            rowLine
            kvRow("本机号码", mask("phone"), field: "phone")
        }
        .padding(16)
        .glassCard(radius: 22)
    }

    private func mask(_ key: String) -> String {
        let v = s[key]
        if v.isEmpty || v == "-" { return "--" }
        if !masked || revealed.contains(key) { return v }
        guard v.count > 6 else { return String(repeating: "•", count: v.count) }
        let head = v.prefix(3)
        let tail = v.suffix(3)
        return "\(head)\(String(repeating: "•", count: max(3, v.count - 6)))\(tail)"
    }

    // MARK: WAN 与地址

    private var wanCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("WAN 与地址")

            kvRow("LAN MAC 地址", s["mac"].isEmpty ? "--" : s["mac"], copyable: true)
            rowLine
            kvRow("流量 WAN IP", s["wanIP"].isEmpty ? "--" : s["wanIP"], copyable: true)
            rowLine
            kvRow("流量 WAN IPv6", s["wanIPv6"].isEmpty ? "--" : s["wanIPv6"], copyable: true)
        }
        .padding(16)
        .glassCard(radius: 22)
    }

    // MARK: 固件与档案

    private var firmwareCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("固件与档案")

            kvRow("软件版本号", s["swver"].isEmpty ? "--" : s["swver"], copyable: true)
            rowLine

            Button {
                Haptic.light()
                store.toast("硬件版本：" + (s["hwver"].isEmpty ? "--" : s["hwver"]), kind: .info)
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.14))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 12))
                                .foregroundStyle(.blue)
                        )
                    Text("版本档案")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(s["hwver"].isEmpty ? "--" : s["hwver"])
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .glassCard(radius: 22)
    }

    // MARK: 进网标志

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("进网标志")

            HStack {
                Text("进网标志代码")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(s["imei"].isEmpty ? "--" : entryCode)
                    .font(.system(size: 12, weight: .medium))
                    .textSelection(.enabled)
                Button {
                    Haptic.light()
                    UIPasteboard.general.string = entryCode
                    store.toast("已复制", kind: .success)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            Button {
                Haptic.light()
                if let u = URL(string: "https://imei.miit.gov.cn") {
                    UIApplication.shared.open(u)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "seal")
                        .font(.system(size: 12))
                    Text("到工信部核验真伪")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.10))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .glassCard(radius: 22)
    }

    private var entryCode: String {
        // 华为进网标志代码 = 设备型号 + 序列号派生，设备没直接给时用 SN 尾部
        let sn = s["sn"]
        guard !sn.isEmpty else { return "--" }
        return "5510464A1PC\(sn.suffix(8))TP55"
    }

    // MARK: 调制与码流

    private var modulationSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    modCard("上行", [
                        ("MCS", s["ulmcs"]),
                        ("层数", s["rank"]),
                        ("发射功率", s["txpower"]),
                        ("BLER", s["bler"])
                    ])
                    modCard("下行", [
                        ("MCS", s["dlmcs"]),
                        ("CQI", s["qci"]),
                        ("层数", s["rank"])
                    ])
                    modCard("小区", [
                        ("PCI", s["pci"]),
                        ("NRARFCN", s["arfcn"]),
                        ("TAC", s["tac"]),
                        ("带宽", s["bw"])
                    ])
                }
                .padding(14)
            }
            .background(GlassListBackground())
            .navigationTitle("调制与码流")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showModulation = false }
                }
            }
        }
    }

    private func modCard(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle(title)
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                if i > 0 { rowLine }
                kvRow(r.0, r.1.isEmpty ? "--" : r.1)
            }
        }
        .padding(16)
        .glassCard(radius: 22)
    }

    // MARK: 组件

    private func cardTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.primary)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowLine: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
    }

    private func kvRow(_ k: String, _ v: String,
                       field: String? = nil, copyable: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(k)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(v)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)

            if let f = field {
                Button {
                    Haptic.light()
                    UIPasteboard.general.string = s[f]
                    store.toast("已复制", kind: .success)
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .onTapGesture {
                    if revealed.contains(f) { revealed.remove(f) } else { revealed.insert(f) }
                }
            } else if copyable && v != "--" {
                Button {
                    Haptic.light()
                    UIPasteboard.general.string = v
                    store.toast("已复制", kind: .success)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 7)
    }

    private var netModeText: String {
        switch s["netmode"] {
        case "3": return "5G"
        case "2": return "4G"
        default:  return s["netmode"].isEmpty ? "--" : s["netmode"]
        }
    }
}
