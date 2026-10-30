import SwiftUI


// MARK: - 液态玻璃卡片

/// 统一的液态玻璃卡片样式（性能优先：单层阴影 + 描边）
struct GlassCard: ViewModifier {
    var radius: CGFloat = 24
    var strong: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground).opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(strong ? 0.9 : 0.65),
                                Color.white.opacity(0.18),
                                Color.white.opacity(strong ? 0.5 : 0.32)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: strong ? 1.2 : 0.9
                    )
            )
    }
}

extension View {
    func glassCard(radius: CGFloat = 24, strong: Bool = false) -> some View {
        modifier(GlassCard(radius: radius, strong: strong))
    }
}


// MARK: - 速率分档配色

/// 实测阈值：≥125 爆速 / ≥100 极速 / ≥20 正常 / ≥5 偏慢 / 其余异常
enum SpeedTier {
    case ultra, fast, normal, slow, bad

    static func of(_ mbps: Double) -> SpeedTier {
        if mbps >= 125 { return .ultra }
        if mbps >= 100 { return .fast }
        if mbps >= 20  { return .normal }
        if mbps >= 5   { return .slow }
        return .bad
    }

    var color: Color {
        switch self {
        case .ultra:  return Color(red: 0.55, green: 0.36, blue: 0.96)  // 紫 #8B5CF6
        case .fast:   return Color(red: 0.09, green: 0.72, blue: 0.65)  // 青绿 #17B8A6
        case .normal: return Color(red: 0.24, green: 0.55, blue: 0.99)  // 蓝 #3D8BFD
        case .slow:   return Color(red: 0.94, green: 0.63, blue: 0.29)  // 橙 #F0A04B
        case .bad:    return Color(red: 0.90, green: 0.34, blue: 0.30)  // 红 #E5574D
        }
    }

    var label: String {
        switch self {
        case .ultra:  return "爆速"
        case .fast:   return "极速"
        case .normal: return "正常"
        case .slow:   return "偏慢"
        case .bad:    return "异常"
        }
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
    @State private var showContract = false
    @AppStorage("customDown") private var customDown: String = ""
    @AppStorage("customUp") private var customUp: String = ""

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
            .onAppear {
                // 从其它 Tab 切回首页时补一次刷新（不重启轮询，交给 scenePhase 管理）
                Task { await store.fetchStatus() }
            }
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
            .sheet(isPresented: $showContract) {
                ContractSheet(down: $customDown, up: $customUp,
                              deviceDown: mbpsFromKbps(s["dlmax"]),
                              deviceUp: mbpsFromKbps(s["ulmax"]))
                    .presentationDetents([.height(340)])
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
                    .background(Capsule().fill(Color(.secondarySystemGroupedBackground).opacity(0.85)))
                }

                Text(s["model"].isEmpty ? "CPE" : s["model"])
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 0) {
                // 左：CPU / 内存
                VStack(alignment: .leading, spacing: 18) {
                    miniStat("CPU 负荷", "\(s.int("cpu"))%", Double(s.int("cpu")) / 100)
                    miniStat("内存占用", "\(memPercent)%", Double(memPercent) / 100)
                }
                .frame(width: 88, alignment: .leading)

                // 中：信号环（占据剩余空间并居中，左右对称）
                signalGauge
                    .frame(maxWidth: .infinity)
                    .frame(height: 148)

                // 右：2×2 功能键 + 设备卡
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        iconBtn("arrow.clockwise") {
                            Task { await store.fetchAll() }
                        }
                        iconBtn("slider.horizontal.3") { showControl = true }
                    }
                    HStack(spacing: 8) {
                        iconBtn("lock.fill") { showLock = true }
                        iconBtn("doc.text") { showParam = true }
                    }
                    Button {
                        showDevices = true
                    } label: {
                        VStack(spacing: 1) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 13))
                                .foregroundStyle(.blue)
                            Text("\(store.hosts.count)")
                                .font(.system(size: 20, weight: .bold))
                            Text("在线设备")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 72, height: 62)
                        .glassCard(radius: 15)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 88)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 19, weight: .bold))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                    .frame(height: 5)
                GeometryReader { g in
                    Capsule()
                        .fill(LinearGradient(colors: [.blue.opacity(0.55), .blue],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, g.size.width * min(1, max(0, p))), height: 5)
                }
                .frame(height: 5)
            }
        }
        .frame(width: 92, alignment: .leading)
    }

    private var signalGauge: some View {
        let rsrp = s.double("rsrp")
        let quality = signalQuality(rsrp)
        // RSRP 映射到 0...1（-140 → 0，-60 → 1）
        let progress = rsrp == 0 ? 0 : min(1, max(0, (rsrp + 140) / 80))

        return ZStack {
            // 底环
            Circle()
                .stroke(Color.secondary.opacity(0.13), lineWidth: 10)
            // 进度弧：从 12 点顺时针
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(quality.color,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)
            VStack(spacing: 1) {
                Text(rsrp == 0 ? "--" : "\(Int(rsrp))")
                    .font(.system(size: 38, weight: .bold))
                    .fixedSize()
                Text("dBm · 信号强度")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Text(quality.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(quality.color)
            }
        }
        .padding(6)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 152)
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
                let ccCount = max(1, store.carriers.count)
                HStack(spacing: 2) {
                    Text("\(ccCount)CC")
                        .font(.system(size: 20, weight: .bold))
                    if ccCount >= 2 {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(ccCount >= 3 ? .purple : .green)
                    }
                }
                .foregroundStyle(ccCount >= 3 ? Color.purple : (ccCount == 2 ? .green : .blue))

                // 多载波时显示各频段
                if ccCount >= 2 {
                    HStack(spacing: 3) {
                        ForEach(store.carriers.prefix(3)) { c in
                            Text(c.displayBand)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .glassCard(radius: 18)
        }
    }

    private func speedBox(_ label: String, _ bps: Double, _ baseColor: Color,
                          showRate: Bool = false) -> some View {
        let mbps = bps / 1_000_000
        let mbs = bps / 8 / 1024 / 1024
        // 分档着色；无数据时用基础色
        let color = mbps > 0 ? SpeedTier.of(mbps).color : baseColor
        return VStack(spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.2f", mbps))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(color)
                Text("Mbps").font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                Text(String(format: "%.2f MB/s", mbs))
                    .font(.system(size: 10.5))
                if mbps > 0 {
                    Text(SpeedTier.of(mbps).label)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(color.opacity(0.15)))
                }
            }
            .foregroundStyle(color.opacity(0.8))
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
                .offset(x: 7, y: -7)
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
            contractItem("签约下行", pick(customDown, s["dlmax"]), "blue", unit: true)
            contractItem("签约上行", pick(customUp, s["ulmax"]),
                         "orange", unit: true, editable: true)
        }
    }

    /// 自定义值优先，空白则用设备值
    private func pick(_ custom: String, _ deviceKbps: String) -> String {
        let c = custom.trimmingCharacters(in: .whitespaces)
        return c.isEmpty ? mbpsFromKbps(deviceKbps) : c
    }

    private func mbpsFromKbps(_ v: String) -> String {
        guard let k = Double(v), k > 0 else { return "--" }
        let m = k / 1000
        return m >= 1000 ? String(format: "%.0f", m) : String(format: "%.1f", m)
    }

    private func contractItem(_ label: String, _ value: String,
                              _ colorName: String, unit: Bool = false,
                              editable: Bool = false) -> some View {
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
        .overlay(alignment: .topTrailing) {
            if editable {
                Button { showContract = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(color)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(color.opacity(0.14)))
                        .overlay(Circle().strokeBorder(color.opacity(0.35), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .offset(x: 7, y: -7)
            }
        }
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
