import SwiftUI

/// 首页 —— 照 CPE Ultra v3.2 的布局
struct HomeView: View {
    @EnvironmentObject var store: CpeStore

    @State private var showDevices = false
    @State private var showModel = false
    @State private var showControl = false
    @State private var showLock = false
    @State private var showParam = false
    @State private var showSms = false
    @State private var showContract = false
    @State private var showSwitcher = false
    @State private var showDiag = false
    @State private var showClearTraffic = false
    @State private var dayQuotaOn = false
    @State private var monthQuotaOn = false
    @AppStorage("customDown") private var customDown: String = ""
    @AppStorage("customUp") private var customUp: String = ""

    private var s: CpeStatus { store.status }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    heroCard
                    speedRow
                    contractCard
                    trafficCard
                    deviceCard
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 96)
            }
            .background(GlassListBackground())
            .navigationBarHidden(true)
            .refreshable { await store.fetchAll() }
            .sheet(isPresented: $showDevices) {
                DeviceSheet(hosts: store.hosts)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showSwitcher) {
                DeviceSwitcher().environmentObject(store)
            }
            .sheet(isPresented: $showControl) { ControlView().environmentObject(store) }
            .sheet(isPresented: $showLock) { LockBandView().environmentObject(store) }
            .sheet(isPresented: $showParam) { ParamView().environmentObject(store) }
            .sheet(isPresented: $showDiag) { DiagView().environmentObject(store) }
        }
    }

    // MARK: - 主卡

    private var heroCard: some View {
        VStack(spacing: 14) {
            // 顶部：运营商 + 制式 + 运行时长
            HStack(spacing: 8) {
                Circle()
                    .fill(s.isOnline ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(s.carrierName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(netModeBadge)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule().fill(
                            LinearGradient(colors: [Color(red: 0.36, green: 0.56, blue: 1.0),
                                                    Color(red: 0.28, green: 0.45, blue: 0.98)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                    )

                Spacer()

                Text("连续运行 " + shortUptime)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            // 信号环
            signalRing
                .frame(width: 200, height: 200)
                .padding(.vertical, 4)

            // 三个小方块：实时下行 / 实时上行 / 载波聚合
            HStack(spacing: 8) {
                miniBox("实时下行", speedValue(store.realtimeRx),
                        unit: speedUnit, sub: byteRate(store.realtimeRx), color: .red)
                miniBox("实时上行", speedValue(store.realtimeTx),
                        unit: speedUnit, sub: byteRate(store.realtimeTx), color: .orange)
                miniBox("载波聚合", ccText, unit: "", sub: nil, color: .blue)
            }

            // CPU / 内存
            HStack(spacing: 0) {
                Text("CPU ")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                Text("\(s.int("cpu"))%")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.blue)
                Text("   ｜   ")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary.opacity(0.4))
                Text("内存 ")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                Text("\(memPercent)%")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.blue)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Color.primary.opacity(0.05))
            )

            // PCC 行
            pccRow
        }
        .padding(14)
        .glassCard(radius: 22)
    }

    /// 信号环
    private var signalRing: some View {
        let rsrp = s.double("rsrp")
        let quality = signalQuality(rsrp)
        let progress = rsrp == 0 ? 0 : min(1, max(0, (rsrp + 140) / 80))

        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.06), lineWidth: 14)

            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.96, green: 0.36, blue: 0.34),
                            Color(red: 0.98, green: 0.66, blue: 0.28),
                            Color(red: 0.95, green: 0.86, blue: 0.32),
                            Color(red: 0.42, green: 0.88, blue: 0.46)
                        ]),
                        center: .center, angle: .degrees(-90)
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.7), value: progress)

            VStack(spacing: 3) {
                Text(rsrp == 0 ? "--" : "\(Int(rsrp))")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(quality.color)
                    .fixedSize()
                Text("dBm · 信号强度")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Text(quality.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(quality.color)
            }
        }
    }

    /// 小方块
    private func miniBox(_ title: String, _ value: String,
                         unit: String, sub: String?, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(color.opacity(0.75))
                }
            }
            if let sb = sub {
                Text(sb)
                    .font(.system(size: 9))
                    .foregroundStyle(color.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    /// PCC 行
    private var pccRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("PCC")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.blue))

                Text("N" + (s["band"].isEmpty ? "--" : s["band"]))
                    .font(.system(size: 19, weight: .bold))
                Text(s["bw"].isEmpty ? "" : "· " + s["bw"])
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Spacer()

                if !s["arfcn"].isEmpty {
                    Text("NRARFCN \(s["arfcn"])")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if !s["pci"].isEmpty {
                    Text("· PCI \(s["pci"])")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                metricCol("RSRP", s["rsrp"], "dBm", -140, -60, .green)
                metricCol("RSRQ", s["rsrq"], "dB", -20, -3, .green)
                metricCol("RSSI", s["rssi"], "dBm", -100, -40, .teal)
                metricCol("SINR", s["sinr"], "dB", 0, 30, .yellow)
            }
        }
    }

    private func metricCol(_ label: String, _ value: String, _ unit: String,
                           _ lo: Double, _ hi: Double, _ color: Color) -> some View {
        let v = Double(value) ?? lo
        let p = min(1, max(0, (v - lo) / (hi - lo)))
        return VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value.isEmpty ? "--" : value)
                    .font(.system(size: 13, weight: .bold))
                Text(unit)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10)).frame(height: 4)
                GeometryReader { g in
                    Capsule().fill(color)
                        .frame(width: max(2, g.size.width * p), height: 4)
                }
                .frame(height: 4)
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var speedRow: some View { EmptyView() }

    // MARK: - SIM 卡签约速率

    private var contractCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("SIM 卡签约速率")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button {
                    Haptic.light()
                    showContract = true
                } label: {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 13))
                        .foregroundStyle(.blue)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.blue.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                contractBox("签约下行", pick(customDown, s["dlmax"]))
                contractBox("签约上行", pick(customUp, s["ulmax"]))
            }

            Button {
                Haptic.light()
                showDiag = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.purple.opacity(0.12)))
                    Text("诊断日志")
                        .font(.system(size: 13.5))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassCard(radius: 22)
    }

    private func contractBox(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func pick(_ custom: String, _ deviceKbps: String) -> String {
        let c = custom.trimmingCharacters(in: .whitespaces)
        if !c.isEmpty { return c + " Mbps" }
        guard let k = Double(deviceKbps), k > 0 else { return "—" }
        let m = k / 1000
        return m >= 100 ? String(format: "%.0f Mbps", m) : String(format: "%.1f Mbps", m)
    }

    // MARK: - 流量统计

    private var trafficCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("流量统计")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text("上次清空 " + monthStartText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                quotaRow("日套餐设置", dayQuotaText, $dayQuotaOn)
                quotaRow("月套餐设置", monthQuotaText, $monthQuotaOn)
            }

            Divider().opacity(0.3)

            VStack(spacing: 0) {
                HStack {
                    Text("类型").frame(width: 54, alignment: .leading)
                    Spacer()
                    Text("当前").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("日").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("月").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)

                HStack {
                    Text("已用").frame(width: 54, alignment: .leading)
                    Spacer()
                    Text(useTotal).frame(maxWidth: .infinity, alignment: .trailing)
                    Text(useDay).frame(maxWidth: .infinity, alignment: .trailing)
                    Text(useMonth).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.vertical, 7)

                HStack {
                    Text("时间").frame(width: 54, alignment: .leading)
                    Spacer()
                    Text(shortUptime).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("—").frame(maxWidth: .infinity, alignment: .trailing)
                    Text(monthDurationText).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.vertical, 7)
            }

            Button {
                Haptic.warning()
                showClearTraffic = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash").font(.system(size: 12))
                    Text("清空流量统计").font(.system(size: 13, weight: .medium))
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
        .padding(14)
        .glassCard(radius: 22)
        .alert("清空流量统计", isPresented: $showClearTraffic) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                Task {
                    let ok = await store.clearTraffic()
                    store.toast(ok ? "已清空" : "清空失败", kind: ok ? .success : .error)
                }
            }
        } message: {
            Text("将重置设备流量计数，不可撤销。")
        }
    }

    private func quotaRow(_ title: String, _ value: String, _ on: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(value)
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
            }
            Spacer()
            Toggle("", isOn: on).labelsHidden().tint(.green)
        }
    }

    // MARK: - 接入设备

    private var deviceCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("接入设备")
                    .font(.system(size: 15, weight: .bold))
                Text("\(store.hosts.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                Spacer()
                Button {
                    Haptic.light()
                    showDevices = true
                } label: {
                    HStack(spacing: 2) {
                        Text("全部")
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color.blue.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }

            if store.hosts.isEmpty {
                Text("暂无在线设备")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                ForEach(Array(store.hosts.prefix(3).enumerated()), id: \.offset) { _, h in
                    hostRow(h)
                }
                if store.hosts.count > 3 {
                    Button {
                        showDevices = true
                    } label: {
                        Text("查看全部 \(store.hosts.count) 台")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .glassCard(radius: 22)
    }

    private func hostRow(_ h: CpeHost) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.blue.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: h.isWired ? "cable.connector" : "wifi")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(h.name.isEmpty ? "设备" : h.name)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                Text(h.ip + (h.mac.isEmpty ? "" : " · " + h.mac))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(h.bandLabel)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .padding(.vertical, 4)
    }

    // MARK: 流量文本

    private var monthStartText: String {
        let v = s["monthStart"]
        return v.isEmpty ? "--" : v
    }
    private var dayQuotaText: String {
        let v = s["dayLimit"]
        return v.isEmpty || v == "0" ? "未设置额度" : v
    }
    private var monthQuotaText: String {
        let v = s["monthLimit"]
        return v.isEmpty || v == "0" ? "未设置额度" : v
    }
    private var useTotal: String {
        let rx = Double(s["totalRx"]) ?? 0
        let tx = Double(s["totalTx"]) ?? 0
        return rx + tx > 0 ? fmtBytes(rx + tx) : bytes(s["monthTotal"])
    }
    private var useDay: String {
        let v = Double(s["todayUsed"]) ?? 0
        return v > 0 ? fmtBytes(v) : "--"
    }
    private var useMonth: String {
        let v = Double(s["monthTotal"]) ?? 0
        return v > 0 ? fmtBytes(v) : "--"
    }
    private var monthDurationText: String {
        let t = Int(s["monthDuration"]) ?? 0
        if t <= 0 { return "--" }
        let d = t / 86400, h = (t % 86400) / 3600
        return "\(d)天\(h)小时"
    }
    private func fmtBytes(_ b: Double) -> String {
        if b >= 1024*1024*1024*1024 { return String(format: "%.2f TB", b/1024/1024/1024/1024) }
        if b >= 1024*1024*1024 {
            let g = b/1024/1024/1024
            return g >= 100 ? String(format: "%.0f GB", g) : String(format: "%.2f GB", g)
        }
        if b >= 1024*1024 { return String(format: "%.0f MB", b/1024/1024) }
        return String(format: "%.0f KB", b/1024)
    }
    private func bytes(_ v: String) -> String {
        guard let b = Double(v), b > 0 else { return "--" }
        return fmtBytes(b)
    }

    // MARK: - 工具

    private var netModeBadge: String {
        s["netmode"] == "3" ? "5G SA" : (s["netmode"] == "2" ? "4G" : "5G")
    }

    private var shortUptime: String {
        let t = s.int("uptime")
        if t <= 0 { return "--" }
        let d = t / 86400, h = (t % 86400) / 3600
        return d > 0 ? "\(d) 天 \(h) 时" : "\(h) 小时"
    }

    private var memPercent: Int {
        let total = s.double("memTotal")
        let free = s.double("memFree")
        guard total > 0 else { return 0 }
        return Int(((total - free) / total * 100).rounded())
    }

    private var speedUnit: String {
        UserDefaults.standard.bool(forKey: "speedAsMBs") ? "MB/s" : "Mbps"
    }

    private func speedValue(_ bps: Double) -> String {
        if UserDefaults.standard.bool(forKey: "speedAsMBs") {
            return String(format: "%.2f", bps / 8 / 1_000_000)
        }
        let m = bps / 1_000_000
        return m < 1 ? String(format: "%.0f", m * 1000) : String(format: "%.1f", m)
    }

    private func byteRate(_ bps: Double) -> String {
        let bytes = bps / 8
        if bytes >= 1_000_000 { return String(format: "%.2f MB/s", bytes / 1_000_000) }
        if bytes >= 1_000 { return String(format: "%.0f KB/s", bytes / 1_000) }
        return String(format: "%.0f B/s", bytes)
    }

    private var ccText: String {
        let n = store.carriers.count
        return "\(max(1, n))CC"
    }

    private func signalQuality(_ r: Double) -> (label: String, color: Color) {
        if r == 0 { return ("未知", .secondary) }
        if r >= -85 { return ("极佳", Color(red: 0.15, green: 0.82, blue: 0.45)) }
        if r >= -95 { return ("良好", Color(red: 0.20, green: 0.78, blue: 0.42)) }
        if r >= -105 { return ("一般", Color(red: 0.98, green: 0.75, blue: 0.25)) }
        if r >= -115 { return ("较差", Color(red: 0.96, green: 0.55, blue: 0.25)) }
        return ("很差", Color(red: 0.94, green: 0.32, blue: 0.30))
    }

    private func tempColor(_ t: Double) -> Color {
        if t >= 50 { return .red }
        if t >= 42 { return .orange }
        return .green
    }
}
