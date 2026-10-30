import SwiftUI


// MARK: - 液态玻璃卡片

/// 统一的液态玻璃卡片样式：渐变 + 描边 + 阴影
struct GlassCard: ViewModifier {
    var radius: CGFloat = 24
    var strong: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(strong ? 0.85 : 0.6),
                                Color.white.opacity(0.15),
                                Color.white.opacity(strong ? 0.55 : 0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: strong ? 1.2 : 0.9
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
            .shadow(color: Color.white.opacity(0.5), radius: 1, x: 0, y: -1)
    }
}

extension View {
    func glassCard(radius: CGFloat = 24, strong: Bool = false) -> some View {
        modifier(GlassCard(radius: radius, strong: strong))
    }
}

struct HomeView: View {
    @EnvironmentObject var store: CpeStore
    @State private var showDevices = false
    @State private var showModel = false
    @State private var showControl = false
    @State private var showLock = false
    @State private var showParam = false
    @State private var showSms = false

    private var s: CpeStatus { store.status }

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    /// 大屏（iPad 横屏 / 分屏宽屏）用双栏
    private var isWide: Bool {
        hSize == .regular && vSize == .regular
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: true) {
                    if isWide {
                        wideLayout(geo: geo)
                    } else {
                        compactLayout
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .background(Color(.systemGroupedBackground))
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationBarHidden(true)
            .refreshable { await store.fetchAll() }
            .sheet(isPresented: $showDevices) {
                DeviceSheet(hosts: store.hosts)
                    .environmentObject(store)
                    .presentationDetents(isWide ? [.large] : [.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showModel) {
                ModelSheet(status: s)
                    .presentationDetents(isWide ? [.large] : [.medium])
            }
            .sheet(isPresented: $showControl) {
                ControlView().environmentObject(store)
            }
            .sheet(isPresented: $showLock) {
                LockBandView().environmentObject(store)
            }
            .sheet(isPresented: $showParam) {
                ParamView().environmentObject(store)
            }
            .sheet(isPresented: $showSms) {
                SmsView().environmentObject(store)
            }
        }
    }

    // MARK: - 紧凑布局（iPhone）

    private var compactLayout: some View {
        VStack(spacing: 14) {
            heroCard
            speedCards
            contractCards
            pccCard
            trafficCard
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 24)
    }

    // MARK: - 宽屏双栏布局（iPad 横屏）

    private func wideLayout(geo: GeometryProxy) -> some View {
        let maxW: CGFloat = 1000
        let contentW = min(geo.size.width - 40, maxW)
        let gap: CGFloat = 16
        // 左右栏 1 : 1.15，右栏略宽容纳 PCC 四列
        let leftW = (contentW - gap) * 0.47

        return HStack(alignment: .top, spacing: gap) {
            VStack(spacing: 14) {
                heroCard
                speedCards
                contractCards
            }
            .frame(width: leftW)

            VStack(spacing: 14) {
                pccCard
                trafficCard
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: contentW)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    // MARK: - 顶部主卡

    private var heroCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(s.isOnline ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(s.carrierName).font(.system(size: 15, weight: .semibold))
                Text(s["netmode"] == "3" ? "5G SA" : "5G")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(LinearGradient(
                        colors: [.blue, .blue.opacity(0.8)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)))

                Spacer()

                if let t = s.temperature {
                    HStack(spacing: 3) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 10))
                        Text(String(format: "%.1f°", t))
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(.ultraThinMaterial))
                }

                Text(s["model"].isEmpty ? "CPE" : s["model"])
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 10) {
                // CPU / 内存
                VStack(spacing: 16) {
                    miniStat("CPU 负荷", "\(s.int("cpu"))%", Double(s.int("cpu")) / 100)
                    miniStat("内存占用", "\(memPercent)%", Double(memPercent) / 100)
                }
                .frame(maxWidth: .infinity)

                // 信号环
                signalGauge
                    .frame(width: 150, height: 150)

                // 右侧功能键 + 设备
                VStack(spacing: 7) {
                    HStack(spacing: 7) {
                        iconBtn("arrow.clockwise") {
                            Task { await store.fetchAll() }
                        }
                        iconBtn("slider.horizontal.3") { showControl = true }
                    }
                    HStack(spacing: 7) {
                        iconBtn("lock.fill") { showLock = true }
                        iconBtn("doc.text") { showParam = true }
                    }
                    Button {
                        showDevices = true
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)
                            Text("\(store.hosts.count)")
                                .font(.system(size: 21, weight: .bold))
                            Text("在线设备")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 76, height: 64)
                        .glassCard(radius: 16)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                Text("连续运行 \(uptimeText)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glassCard(radius: 24, strong: true)
    }

    private var memPercent: Int {
        let total = s.int("memTotal"), free = s.int("memFree")
        guard total > 0 else { return 0 }
        return Int(Double(total - free) / Double(total) * 100)
    }

    private func miniStat(_ label: String, _ value: String, _ p: Double) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 18, weight: .bold))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule().fill(LinearGradient(colors: [.blue.opacity(0.6), .blue],
                                                 startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, g.size.width * min(1, max(0, p))))
                }
            }
            .frame(height: 5)
        }
    }

    private var signalGauge: some View {
        let rsrp = s.double("rsrp")
        let quality = signalQuality(rsrp)
        // RSRP 映射到 0...1（-140 → 0，-60 → 1）
        let progress = rsrp == 0 ? 0 : min(1, max(0, (rsrp + 140) / 80))

        return ZStack {
            // 底环
            Circle()
                .stroke(Color.secondary.opacity(0.13),
                        style: StrokeStyle(lineWidth: 10, lineCap: .butt))
            // 进度弧：从 12 点顺时针
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(quality.color,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round,
                                           lineJoin: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: quality.color.opacity(0.35), radius: 5)
                .animation(.easeInOut(duration: 0.6), value: progress)
            VStack(spacing: 1) {
                Text(rsrp == 0 ? "--" : "\(Int(rsrp))")
                    .font(.system(size: 38, weight: .bold))
                Text("dBm · 信号强度").font(.system(size: 9.5)).foregroundStyle(.secondary)
                Text(quality.label).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(quality.color)
            }
        }
    }

    private func signalQuality(_ r: Double) -> (label: String, color: Color) {
        if r >= -85 { return ("极佳", .blue) }
        if r >= -95 { return ("优", .green) }
        if r >= -105 { return ("良", .green) }
        if r >= -115 { return ("中", .orange) }
        return ("弱", .red)
    }

    private func iconBtn(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 32)
                .glassCard(radius: 11)
        }
        .buttonStyle(.plain)
    }

    private var uptimeText: String {
        let h = store.status.int("uptime") / 3600
        return h > 0 ? "\(h) 小时" : "\(store.status.int("uptime") / 60) 分钟"
    }

    // MARK: - 速率卡

    private var speedCards: some View {
        HStack(spacing: 9) {
            speedBox("实时下行", store.realtimeRx, .blue)
            speedBox("实时上行", store.realtimeTx, .orange, showRate: true)
            VStack(spacing: 2) {
                Text("载波聚合").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("\(max(1, s.int("sccNum") + 1))CC")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.blue)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassCard(radius: 18)
        }
    }

    private func speedBox(_ label: String, _ bps: Double, _ color: Color,
                          showRate: Bool = false) -> some View {
        let mbps = bps / 1_000_000
        let mbs = bps / 8 / 1024 / 1024
        return VStack(spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.2f", mbps))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(color)
                Text("Mbps").font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
            Text(String(format: "%.2f MB/s", mbs))
                .font(.system(size: 10.5))
                .foregroundStyle(color.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .overlay(alignment: .topTrailing) {
            if showRate {
                Menu {
                    ForEach([0.5, 1.0, 1.5, 2.0, 3.0, 5.0], id: \.self) { v in
                        Button {
                            store.refreshInterval = v
                            store.startPolling()
                        } label: {
                            if store.refreshInterval == v {
                                Label(rateLabel(v), systemImage: "checkmark")
                            } else {
                                Text(rateLabel(v))
                            }
                        }
                    }
                } label: {
                    Text(rateLabel(store.refreshInterval))
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(color.opacity(0.14)))
                        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.8))
                }
                .offset(x: -6, y: 6)
            }
        }
        .glassCard(radius: 18)
    }

    private func rateLabel(_ v: Double) -> String {
        v == floor(v) ? "\(Int(v))s" : String(format: "%.1fs", v)
    }

    // MARK: - 签约卡

    private var contractCards: some View {
        HStack(spacing: 9) {
            contractItem("QCI", s["qci"], "teal")
            contractItem("签约下行", mbpsFromKbps(s["dlmax"]), "blue", unit: true)
            contractItem("签约上行", mbpsFromKbps(s["ulmax"]), "orange", unit: true)
        }
    }

    private func mbpsFromKbps(_ v: String) -> String {
        guard let k = Double(v), k > 0 else { return "--" }
        let m = k / 1000
        return m >= 1000 ? String(format: "%.0f", m) : String(format: "%.1f", m)
    }

    private func contractItem(_ label: String, _ value: String,
                              _ colorName: String, unit: Bool = false) -> some View {
        let color: Color = colorName == "teal" ? .teal
            : (colorName == "blue" ? .blue : .orange)
        return VStack(spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.isEmpty ? "--" : value)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(color)
                if unit { Text("Mbps").font(.system(size: 9.5)).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .glassCard(radius: 18)
    }

    // MARK: - PCC

    private var pccCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 9) {
                Text("PCC")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 9).fill(.blue))
                Text("N" + (s["band"].isEmpty ? "--" : s["band"]))
                    .font(.system(size: 20, weight: .bold))
                Text(s["bw"]).font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                pccKV("NRARFCN", s["arfcn"])
                pccKV("PCI", s["pci"])
            }

            HStack(spacing: 0) {
                kpi("RSRP", s["rsrp"], "dBm", -140, -60)
                kpi("RSRQ", s["rsrq"], "dB", -20, -3)
                kpi("RSSI", s["rssi"], "dBm", -100, -40)
                kpi("SINR", s["sinr"], "dB", 0, 30)
            }
        }
        .padding(16)
        .glassCard(radius: 24)
    }

    private func pccKV(_ k: String, _ v: String) -> some View {
        VStack(spacing: 1) {
            Text(k).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(v.isEmpty ? "--" : v).font(.system(size: 13, weight: .bold))
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .glassCard(radius: 10)
        .padding(.leading, 6)
    }

    private func kpi(_ label: String, _ v: String, _ unit: String,
                     _ lo: Double, _ hi: Double) -> some View {
        let val = Double(v) ?? 0
        let p = Swift.min(1, Swift.max(0, (val - lo) / (hi - lo)))
        return VStack(spacing: 3) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(v.isEmpty ? "--" : v).font(.system(size: 15, weight: .bold))
                Text(unit).font(.system(size: 8.5)).foregroundStyle(.secondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(.teal).frame(width: max(2, g.size.width * p))
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 流量

    private var trafficCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("流量统计").font(.system(size: 16, weight: .bold))
                Spacer()
                Text("本月累计").font(.system(size: 12)).foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text("今日")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                Spacer()
                legend("下行", todayRx, .blue)
                legend("上行", todayTx, .orange)
                legend("合计", bytes(s["todayTotal"]), .secondary)
            }

            HStack(spacing: 9) {
                tile("本月合计", bytes(s["monthTotal"]), .primary)
                tile("下行", bytes(s["monthRx"]), .blue)
                tile("上行", bytes(s["monthTx"]), .orange)
            }
        }
        .padding(16)
        .glassCard(radius: 24)
    }

    /// 设备只提供 TodayTotalBytes，无分方向字段
    /// 用本月上下行比例拆分今日合计（近似值）
    private var todayRx: String {
        let total = s.double("todayTotal")
        let mRx = s.double("monthRx"), mTx = s.double("monthTx")
        guard total > 0, mRx + mTx > 0 else { return "--" }
        return bytes(String(Int(total * mRx / (mRx + mTx))))
    }

    private var todayTx: String {
        let total = s.double("todayTotal")
        let mRx = s.double("monthRx"), mTx = s.double("monthTx")
        guard total > 0, mRx + mTx > 0 else { return "--" }
        return bytes(String(Int(total * mTx / (mRx + mTx))))
    }

    private func bytes(_ v: String) -> String {
        guard let n = Double(v), n > 0 else { return "--" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var val = n, i = 0
        while val >= 1024 && i < units.count - 1 { val /= 1024; i += 1 }
        return String(format: val >= 100 ? "%.0f %@" : "%.2f %@", val, units[i])
    }

    private func legend(_ label: String, _ v: String, _ c: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(c).frame(width: 5, height: 5)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(v).font(.system(size: 11.5, weight: .bold)).foregroundStyle(c)
        }
    }

    private func tile(_ label: String, _ v: String, _ c: Color) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Text(v).font(.system(size: 16, weight: .bold)).foregroundStyle(c)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .glassCard(radius: 15)
    }

}
