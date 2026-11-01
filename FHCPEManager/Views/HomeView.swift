import SwiftUI


struct HomeView: View {
    @EnvironmentObject var store: CpeStore
    @EnvironmentObject var router: TabRouter
    @State private var showDevices = false
    @State private var showModel = false
    @State private var showControl = false
    @State private var showLock = false
    @State private var showParam = false
    @State private var showSms = false
    @State private var showContract = false
    @State private var showSwitcher = false
    @State private var showRebootConfirm = false
    @State private var rebooting = false
    @AppStorage("customDown") private var customDown: String = ""
    @AppStorage("customUp") private var customUp: String = ""

    private var s: CpeStatus { store.status }

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: true) {
                    // 始终单栏；宽屏时限制最大宽度并水平居中，保持与分屏一致的观感
                    compactLayout
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .background(Color(.systemGroupedBackground))
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationBarHidden(true)
            // 设备变化提醒（Wi-Fi 切换后出现）
            .safeAreaInset(edge: .top, spacing: 0) {
                if let p = store.detectedProfile {
                    switchBanner(p)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if store.currentOffline {
                    offlineBanner
                        .padding(.horizontal, 14)
                        .padding(.bottom, 6)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.detectedProfile?.id)
            .refreshable { await store.fetchAll() }
            .onAppear {
                // 从其它 Tab 切回首页时补一次刷新（不重启轮询，交给 scenePhase 管理）
                Task { await store.fetchStatus() }
            }
            .sheet(isPresented: $showDevices) {
                DeviceSheet(hosts: store.hosts)
                    .environmentObject(store)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showModel) {
                ModelSheet(status: s)
                    .presentationDetents([.medium])
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
            .alert("重启设备", isPresented: $showRebootConfirm) {
                Button("取消", role: .cancel) { }
                Button("重启", role: .destructive) {
                    guard !rebooting else { return }
                    rebooting = true
                    Haptic.warning()
                    Task {
                        let ok = await store.reboot()
                        rebooting = false
                        store.toast(ok ? "重启指令已发送，设备将在 1 分钟内恢复"
                                       : "重启失败，请检查连接",
                                    kind: ok ? .success : .error)
                    }
                }
            } message: {
                Text("重启期间所有设备会断开网络，约需 1 分钟恢复。\n\n确定要重启吗？")
            }
            .sheet(isPresented: $showSwitcher) {
                DeviceSwitcher()
                    .environmentObject(store)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSms) {
                SmsView().environmentObject(store)
            }
            .sheet(isPresented: $showContract) {
                ContractSheet(down: $customDown, up: $customUp,
                              deviceDown: mbpsFromKbps(s["dlmax"]),
                              deviceUp: mbpsFromKbps(s["ulmax"]))
                    .environmentObject(store)
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

                // 重启按钮（设备选择左边）
                Button {
                    Haptic.warning()
                    showRebootConfirm = true
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.85))
                        .frame(width: 28, height: 26)
                        .background(Capsule().fill(Color.red.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 2)

                // 设备型号：点击切换设备
                Button {
                    Haptic.light()
                    showSwitcher = true
                } label: {
                    HStack(spacing: 4) {
                        Text(deviceTitle)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .center, spacing: 0) {
                // 左：CPU / 内存 / 温度
                VStack(alignment: .leading, spacing: 14) {
                    miniStat("CPU 负荷", "\(s.int("cpu"))%", Double(s.int("cpu")) / 100)
                    miniStat("内存占用", "\(memPercent)%", Double(memPercent) / 100)
                    if let t = s.temperature {
                        // 只保留图标 + 数值，省掉「模组温度」文字
                        HStack(spacing: 3) {
                            Image(systemName: "thermometer.medium")
                                .font(.system(size: 12))
                            Text(String(format: "%.1f°C", t))
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundStyle(tempColor(t))
                        .frame(width: 88, alignment: .leading)
                    }
                }
                .frame(width: 88, alignment: .leading)

                // 中：信号环（占据剩余空间并居中，左右对称）
                signalGauge
                    .frame(maxWidth: .infinity)
                    .frame(height: 148)

                // 右：2×2 功能键 + 设备卡（网格均分，四个按钮完全等大）
                VStack(spacing: 8) {
                    Grid(horizontalSpacing: 7, verticalSpacing: 7) {
                        GridRow {
                            iconBtn("arrow.clockwise", "刷新") {
                                store.toast("正在刷新…", kind: .info)
                                Task { await store.fetchAll() }
                            }
                            iconBtn("slider.horizontal.3", "控制") { router.go(.control) }
                        }
                        GridRow {
                            iconBtn("lock.fill", "锁频") { router.go(.lock) }
                            iconBtn("doc.text", "参数") { router.go(.param) }
                        }
                    }
                    .frame(width: 92)

                    Button {
                        showDevices = true
                    } label: {
                        VStack(spacing: 1) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 13))
                                .foregroundStyle(.blue)
                            Text("\(onlineDeviceCount)")
                                .font(.system(size: 20, weight: .bold))
                            Text("在线设备")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 84, height: 62)
                        .glassCard(radius: 15)
                    }
                    .buttonStyle(.plain)
                    .haptic()
                }
                .frame(width: 84)
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

    /// 温度配色：<42 散热良好，42~50 偏热，>50 过热
    private func tempColor(_ t: Double) -> Color {
        if t >= 50 { return .red }
        if t >= 42 { return .orange }
        return .green
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

    /// 图标 + 文字的小功能键（42×42）
    private func iconBtn(_ name: String, _ title: String,
                         action: @escaping () -> Void) -> some View {
        Button {
            Haptic.light()
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 42, height: 42)
            .glassCard(radius: 12)
        }
        .buttonStyle(.plain)
    }

    /// 连续运行时间：精确到分钟。3 天 5 小时 12 分钟
    private var uptimeText: String {
        let total = max(0, store.status.int("uptime"))       // 秒
        if total == 0 { return "--" }
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let mins = (total % 3600) / 60

        if days > 0 {
            return hours > 0 ? "\(days) 天 \(hours) 小时 \(mins) 分钟"
                             : "\(days) 天 \(mins) 分钟"
        }
        if hours > 0 {
            return mins > 0 ? "\(hours) 小时 \(mins) 分钟" : "\(hours) 小时"
        }
        return "\(mins) 分钟"
    }

    // MARK: - 速率卡

    private var speedCards: some View {
        HStack(spacing: 9) {
            speedBox("实时下行", store.realtimeRx, .blue)
            speedBox("实时上行", store.realtimeTx, .orange, showRate: true)
            VStack(spacing: 2) {
                Text("载波聚合").font(.system(size: 11)).foregroundStyle(.secondary)
                let ccCount = max(1, store.carriers.count)
                let tierColor: Color = ccCount >= 3 ? .purple : (ccCount == 2 ? .green : .blue)

                Text("\(ccCount)CC")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(tierColor)

                // 多载波时把各频段做成一排小胶囊
                if ccCount >= 2 {
                    HStack(spacing: 4) {
                        ForEach(Array(store.carriers.prefix(3))) { c in
                            Text(c.displayBand)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(c.isPrimary ? Color.blue : Color.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill((c.isPrimary ? Color.blue : Color.orange).opacity(0.13))
                                )
                        }
                    }
                    .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)          // 与速率卡完全等高等宽
            .glassCard(radius: 18)
        }
    }

    private func speedBox(_ label: String, _ bps: Double, _ baseColor: Color,
                          showRate: Bool = false) -> some View {
        let mbps = bps / 1_000_000
        let mbs = bps / 8 / 1024 / 1024
        let tier = SpeedTier.of(mbps)
        let color = mbps > 0 ? tier.color : baseColor

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(height: 15)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(String(format: "%.2f", mbps))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("Mbps")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(color.opacity(0.55))
            }
            .frame(height: 26)

            Text(String(format: "%.2f MB/s", mbs))
                .font(.system(size: 10))
                .foregroundStyle(color.opacity(0.72))   // 与 Mbps 同色系
                .frame(height: 14)

            if mbps > 0 {
                Text(tier.emoji + " " + tier.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tier.color)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tier.color.opacity(0.12)))
                    .frame(height: 18)
            } else {
                Color.clear.frame(height: 18)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)                          // 固定高度，绝不因内容变化
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
                        .frame(height: 18)
                        .padding(.horizontal, 7)
                        .background(Capsule().fill(Color(.systemBackground)))
                        .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
                }
                .offset(x: 4, y: -4)                // 压在卡片右上角边框上
                .haptic()
            }
        }
        .glassCard(radius: 18)
    }

    private func rateLabel(_ v: Double) -> String {
        v == floor(v) ? "\(Int(v))s" : String(format: "%.1fs", v)
    }

    // MARK: - 签约卡

    /// QCI 等级说明：1~5 信令/语音，6~9 数据业务
    private var qciSubtitle: String {
        guard let q = Int(s["qci"]), q > 0 else { return "—" }
        switch q {
        case 1: return "语音"
        case 2: return "视频通话"
        case 3: return "游戏"
        case 4: return "串流"
        case 5: return "信令"
        case 6: return "普通数据"
        case 7: return "流媒体"
        case 8: return "后台"
        case 9: return "尽力而为"
        default: return "等级 \(q)"
        }
    }

    private var contractCards: some View {
        Group {
            if store.isOppo || store.isHuawei {
                // OPPO / 华为：显示小区标识
                HStack(spacing: 9) {
                    contractItem("频段", s["band"].isEmpty ? "--" : "n" + s["band"],
                                 "teal", subtitle: oppoBandHint)
                    contractItem("PCI", s["pci"], "blue")
                    contractItem("网络", s["netmode"] == "3" ? "5G" : "4G", "orange")
                }
            } else {
                HStack(spacing: 9) {
                    contractItem("QCI", s["qci"], "teal", subtitle: qciSubtitle)
                    contractItem("签约下行", pick(customDown, s["dlmax"]), "blue", unit: true)
                    contractItem("签约上行", pick(customUp, s["ulmax"]),
                                 "orange", unit: true, editable: true)
                }
            }
        }
    }

    /// OPPO 频段补充说明（n78 = 3.5GHz 主力频段）
    private var oppoBandHint: String {
        switch s["band"] {
        case "78", "77", "79": return "3.5GHz"
        case "1", "3":         return "1.8GHz"
        case "28":             return "700MHz"
        case "41":             return "2.6GHz"
        default:               return "5G"
        }
    }

    /// 自定义值优先，空白则用设备值
    private func pick(_ custom: String, _ deviceKbps: String) -> String {
        let c = custom.trimmingCharacters(in: .whitespaces)
        return c.isEmpty ? mbpsFromKbps(deviceKbps) : c
    }

    /// AMBR 单位是 Kbps，签约速率通常是整百，去掉无意义的小数
    private func mbpsFromKbps(_ v: String) -> String {
        guard let k = Double(v), k > 0 else { return "--" }
        let m = k / 1000
        // 307.2 → 307，3072 → 3072
        if m >= 100 { return String(format: "%.0f", m) }
        if m == m.rounded() { return String(format: "%.0f", m) }
        return String(format: "%.1f", m)
    }

    private func contractItem(_ label: String, _ value: String,
                              _ colorName: String, unit: Bool = false,
                              editable: Bool = false, subtitle: String? = nil) -> some View {
        let color: Color = colorName == "teal" ? .teal
            : (colorName == "blue" ? .blue : .orange)
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(height: 15)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value.isEmpty ? "--" : value)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if unit {
                    Text("Mbps")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(color.opacity(0.55))
                }
            }
            .frame(height: 26)

            Color.clear.frame(height: 18)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)                          // 与速率卡等高
        .overlay(alignment: .topTrailing) {
            if editable {
                Button { showContract = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(color)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color(.systemBackground)))
                        .overlay(Circle().strokeBorder(color.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .haptic(.medium)
                .offset(x: 4, y: -4)                // 压在卡片右上角边框上
            }
        }
        .glassCard(radius: 18)
    }

    private var pccCard: some View {
        VStack(spacing: 12) {
            // 每个载波一张子卡
            ForEach(Array(store.carriers.enumerated()), id: \.element.id) { idx, c in
                carrierRow(c, showDivider: idx > 0)
            }

            // 没有载波数据时用旧数据兜底
            if store.carriers.isEmpty {
                carrierRowFromStatus()
            }
        }
        .padding(14)
        .glassCard(radius: 24)
    }

    /// 单个载波信息行
    private func carrierRow(_ c: CarrierComponent, showDivider: Bool) -> some View {
        VStack(spacing: 10) {
            if showDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.6))
                    .frame(height: 1)
                    .padding(.vertical, 2)
            }

            HStack(spacing: 8) {
                Text(c.tag)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(c.isPrimary ? Color.blue : Color.orange)
                    )

                Text(c.displayBand)
                    .font(.system(size: 19, weight: .bold))

                if !c.bandwidth.isEmpty {
                    Text(c.bandwidth)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !c.arfcn.isEmpty {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("NRARFCN").font(.system(size: 8.5)).foregroundStyle(.secondary)
                        Text(c.arfcn).font(.system(size: 11.5, weight: .semibold))
                    }
                }
                if !c.pci.isEmpty {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("PCI").font(.system(size: 8.5)).foregroundStyle(.secondary)
                        Text(c.pci).font(.system(size: 11.5, weight: .semibold))
                    }
                }
            }

            // 四指标
            HStack(spacing: 0) {
                metricCell("RSRP", c.rsrp, "dBm", -140, -60)
                metricCell("RSRQ", c.rsrq, "dB", -20, -3)
                metricCell("RSSI", c.rssi, "dBm", -100, -40)
                metricCell("SINR", c.sinr, "dB", 0, 30)
            }
        }
    }

    /// 单载波兜底（沿用 status 里的主小区数据）
    private func carrierRowFromStatus() -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("PCC")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2.5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.blue))
                Text("N" + (s["band"].isEmpty ? "--" : s["band"]))
                    .font(.system(size: 19, weight: .bold))
                Text(s["bw"]).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if !s["arfcn"].isEmpty {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("NRARFCN").font(.system(size: 8.5)).foregroundStyle(.secondary)
                        Text(s["arfcn"]).font(.system(size: 11.5, weight: .semibold))
                    }
                }
                if !s["pci"].isEmpty {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("PCI").font(.system(size: 8.5)).foregroundStyle(.secondary)
                        Text(s["pci"]).font(.system(size: 11.5, weight: .semibold))
                    }
                }
            }
            HStack(spacing: 0) {
                metricCell("RSRP", s["rsrp"], "dBm", -140, -60)
                metricCell("RSRQ", s["rsrq"], "dB", -20, -3)
                metricCell("RSSI", s["rssi"], "dBm", -100, -40)
                metricCell("SINR", s["sinr"], "dB", 0, 30)
            }
        }
    }

    /// 指标单元（带彩色进度条）
    private func metricCell(_ label: String, _ value: String, _ unit: String,
                            _ lo: Double, _ hi: Double) -> some View {
        let v = Double(value) ?? 0
        let p = min(1, max(0, (v - lo) / (hi - lo)))
        let color = metricColor(label, v)
        return VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value.isEmpty ? "--" : value)
                    .font(.system(size: 14, weight: .bold))
                Text(unit).font(.system(size: 8)).foregroundStyle(.secondary)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 4)
                GeometryReader { g in
                    Capsule().fill(color)
                        .frame(width: max(3, g.size.width * p), height: 4)
                }
                .frame(height: 4)
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricColor(_ label: String, _ v: Double) -> Color {
        switch label {
        case "RSRP":
            if v > -85 { return .blue }
            if v > -100 { return .green }
            if v > -110 { return .orange }
            return .red
        case "RSRQ":
            if v > -10 { return .green }
            if v > -15 { return .orange }
            return .red
        case "RSSI":
            if v > -65 { return .teal }
            if v > -80 { return .orange }
            return .red
        case "SINR":
            if v >= 13 { return .green }
            if v >= 5 { return .orange }
            return .red
        default:
            return .blue
        }
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

    /// 检测到另一台设备 → 提醒切换
    private func switchBanner(_ p: CpeProfile) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text("检测到 \(p.displayTitle)")
                    .font(.system(size: 13, weight: .semibold))
                Text(p.host + " · 是否切换？")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button("忽略") {
                Haptic.light()
                store.dismissDetected()
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)

            Button("切换") {
                Haptic.medium()
                Task { await store.switchTo(p) }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.blue))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    /// 当前设备断开
    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13))
                .foregroundStyle(.red)
            Text("当前设备已断开，请检查 Wi-Fi")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
        )
    }

    /// 顶栏设备名：
    /// 烽火显示真实型号（LG6121F），OPPO 显示简称（OPPO）
    private var deviceTitle: String {
        if store.isOppo {
            return store.activeProfile?.displayTitle ?? "OPPO"
        }
        if store.isHuawei {
            let m = s.deviceModel
            return (m.isEmpty || m == "CPE") ? "华为" : m
        }
        // 烽火：优先显示设备型号
        let model = s.deviceModel
        if !model.isEmpty && model != "CPE" { return model }
        return store.activeProfile?.displayTitle ?? "CPE"
    }

    /// 在线设备数：烽火用 hosts，OPPO 用页面识别到的数量
    private var onlineDeviceCount: Int {
        if store.isOppo || store.isHuawei {
            return Int(s["online"]) ?? 0
        }
        return store.hosts.count
    }

    // MARK: - 流量标注

    /// 设备流量计数器约 12.5 秒刷新一次
    private var trafficIntervalText: String {
        let base = store.isOppo ? "实时更新" : "设备约 12 秒更新"
        guard let t = store.trafficUpdatedAt else { return base }
        let sec = Int(Date().timeIntervalSince(t))
        return sec < 2 ? "刚刚更新" : "\(base) · \(sec)s 前"
    }


    /// 今日流量单项：标签 + 数值 + 下方增量
    private func todayItem(_ label: String, _ value: String,
                           _ color: Color, _ delta: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            // 增量：有变化才显示，占位保持不跳动
            Text(delta > 0 ? "+ " + compactBytes(delta) : " ")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color.opacity(0.75))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// 紧凑字节格式：123 MB / 1.2 GB
    private func compactBytes(_ n: Double) -> String {
        if n >= 1024 * 1024 * 1024 {
            return String(format: "%.2f GB", n / 1024 / 1024 / 1024)
        }
        if n >= 1024 * 1024 {
            return String(format: "%.1f MB", n / 1024 / 1024)
        }
        return String(format: "%.0f KB", n / 1024)
    }

    private var trafficCard: some View {
        VStack(spacing: 10) {
            // 标题行：左上标题，右上更新周期
            HStack {
                Text("流量统计").font(.system(size: 16, weight: .bold))
                Spacer()
                Text(trafficIntervalText)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary.opacity(0.8))
            }

            if store.isOppo {
                // OPPO 只有累计值，不提供今日/本月分项
                trafficGroup("累计", rx: bytes(s["monthRx"]), tx: bytes(s["monthTx"]),
                             total: bytes(s["monthTotal"]),
                             dRx: store.todayRxDelta, dTx: store.todayTxDelta)

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                    Text("设备累计值，不支持今日/本月分项")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.secondary.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                trafficGroup("今日", rx: todayRx, tx: todayTx, total: bytes(s["todayTotal"]),
                             dRx: store.todayRxDelta, dTx: store.todayTxDelta)

                Divider().opacity(0.35)

                trafficGroup("本月", rx: bytes(s["monthRx"]), tx: bytes(s["monthTx"]),
                             total: bytes(s["monthTotal"]), dRx: 0, dTx: 0)
            }
        }
        .padding(16)
        .glassCard(radius: 24)
    }

    /// 一组流量：左侧标签 + 右侧三项（下行 / 上行 / 合计）
    private func trafficGroup(_ title: String,
                              rx: String, tx: String, total: String,
                              dRx: Double, dTx: Double) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
                .padding(.top, 1)

            trafficCell("下行", rx, .blue, dRx)
                .frame(maxWidth: .infinity, alignment: .leading)
            trafficCell("上行", tx, .orange, dTx)
                .frame(maxWidth: .infinity, alignment: .leading)
            trafficCell("合计", total, .secondary, 0)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 单项流量：小圆点 + 标签 / 数值 / 增量
    private func trafficCell(_ label: String, _ value: String,
                             _ color: Color, _ delta: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            // 增量行始终占位（无增量时空一行），保证三项等高对齐
            Text(delta > 0 ? "+ " + compactBytes(delta) : " ")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(color.opacity(0.7))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// 设备只提供 TodayTotalBytes，无分方向字段
    /// 用本月上下行比例拆分今日合计（近似值）
    /// 今日下行：按本月上下行比例拆分今日合计，统一走 bytes() 保证两位小数
    private var todayRx: String {
        let total = s.double("todayTotal")
        let mRx = s.double("monthRx"), mTx = s.double("monthTx")
        guard total > 0, mRx + mTx > 0 else { return "--" }
        return bytes(String(format: "%.0f", total * mRx / (mRx + mTx)))
    }

    /// 今日上行：同上，保证与下行同样精度
    private var todayTx: String {
        let total = s.double("todayTotal")
        let mRx = s.double("monthRx"), mTx = s.double("monthTx")
        guard total > 0, mRx + mTx > 0 else { return "--" }
        return bytes(String(format: "%.0f", total * mTx / (mRx + mTx)))
    }

    private func bytes(_ v: String) -> String {
        guard let n = Double(v), n > 0 else { return "--" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var val = n, i = 0
        while val >= 1024 && i < units.count - 1 { val /= 1024; i += 1 }
        // 统一两位小数，与「70.88 GB」一致
        return String(format: "%.2f %@", val, units[i])
    }

    private func legend(_ label: String, _ v: String, _ c: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(c).frame(width: 5, height: 5)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(v)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(c)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)   // 禁止折成两行
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
