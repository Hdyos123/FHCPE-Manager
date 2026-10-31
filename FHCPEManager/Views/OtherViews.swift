import SwiftUI
import UIKit

import SwiftUI

// MARK: - 控制

struct ControlView: View {
    @EnvironmentObject var store: CpeStore
    @State private var pendingToggle: (node: String, on: Bool, label: String)?
    @State private var showReboot = false
    @State private var localOverride: [String: Bool] = [:]
    @State private var busyNode: String?

    private var s: CpeStatus { store.status }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusBanner

                    // 2×2 开关卡片（一屏可见，无需滚动）
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                        GridItem(.flexible(), spacing: 10)],
                              spacing: 10) {
                        switchCard("飞行模式", "airplane",
                                   CpeNode.netSet + "airplan_on", "airplane", .orange)
                        switchCard("数据漫游", "roaming",
                                   CpeNode.netSet + "RoamingEnable", "roaming", .blue)
                        switchCard("VoLTE", "volte",
                                   CpeNode.netSet + "volte_switch", "volte", .green)
                        switchCard("载波聚合", "ca",
                                   "X_FH_MobileNetwork.NetworkInfo.CaEnable", "ca", .purple)
                    }

                    rebootButton
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
            .background(GlassListBackground())
            .navigationTitle("控制")
            .alert("确认操作", isPresented: Binding(
                get: { pendingToggle != nil },
                set: { if !$0 { pendingToggle = nil } }
            )) {
                Button("取消", role: .cancel) { pendingToggle = nil }
                Button("确定") {
                    Haptic.medium()
                    applyToggle()
                }
            } message: {
                if let p = pendingToggle {
                    Text("确定要\(p.on ? "开启" : "关闭")\(p.label)吗？")
                }
            }
            .alert("重启设备", isPresented: $showReboot) {
                Button("取消", role: .cancel) { }
                Button("重启", role: .destructive) {
                    Haptic.warning()
                    Task {
                        let ok = await store.reboot()
                        store.toast(ok ? "重启指令已发送" : "重启失败", kind: ok ? .success : .error)
                    }
                }
            } message: {
                Text("重启期间所有设备将断开网络，约需 1 分钟恢复。")
            }
        }
    }

    // MARK: 组件

    private var statusBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(s.isOnline ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.isOnline ? "网络正常" : "网络异常")
                    .font(.system(size: 14, weight: .semibold))
                Text(s.carrierName + " · N" + (s["band"].isEmpty ? "--" : s["band"]))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(s.double("rsrp"))) dBm")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .glassCard(radius: 16)
    }

    private func switchCard(_ title: String, _ key: String, _ node: String,
                            _ icon: String, _ tint: Color) -> some View {
        let raw = (localOverride[node] ?? (s[key].lowercased() == "1"
                 || s[key].lowercased() == "true")).description
        let isOn = raw == "true"
        let busy = busyNode == node

        return Button {
            pendingToggle = (node, !isOn, title)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isOn ? tint : Color.secondary)
                    Spacer()
                    if busy {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text(isOn ? "开" : "关")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(isOn ? tint : Color.secondary.opacity(0.3)))
                    }
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(isOn ? "已开启" : "已关闭")
                    .font(.system(size: 10.5))
                    .foregroundStyle(isOn ? tint : Color.secondary)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 104)
            .glassCard(radius: 18)
        }
        .buttonStyle(.plain)
        .haptic(.medium)
    }

    private var rebootButton: some View {
        Button { showReboot = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "power")
                    .font(.system(size: 15, weight: .medium))
                Text("重启设备")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.9, green: 0.3, blue: 0.3))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .glassCard(radius: 16)
        }
        .buttonStyle(.plain)
        .haptic(.warning)
    }

    private func applyToggle() {
        guard let p = pendingToggle else { return }
        pendingToggle = nil
        busyNode = p.node
        localOverride[p.node] = p.on
        Task {
            let ok = await store.setToggle(node: p.node, on: p.on)
            busyNode = nil
            if !ok {
                localOverride.removeValue(forKey: p.node)
                store.toast("设置失败，请重试", kind: .error)
            } else {
                store.toast(p.label + (p.on ? " 已开启" : " 已关闭"), kind: .success)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                localOverride.removeValue(forKey: p.node)
            }
        }
    }
}

// MARK: - 参数

struct ParamView: View {
    @EnvironmentObject var store: CpeStore
    @State private var masked = true

    private var s: CpeStatus { store.status }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // 概览卡：型号 + 温度
                    overviewCard

                    // 3 组两列信息
                    infoCard("CPE 信息", icon: "cpu", rows: [
                        ("序列号", masked ? "••••••••" : s["sn"]),
                        ("厂商", s["vendor"]),
                        ("软件版本", s["swver"]),
                        ("硬件版本", s["hwver"]),
                        ("工作模式", s["workmode"]),
                        ("模组版本", s["modem"])
                    ])

                    infoCard("网络", icon: "wifi", rows: [
                        ("WAN IP", s["wanIP"]),
                        ("LAN IP", s["lanIP"]),
                        ("2.4G SSID", s["ssid24"]),
                        ("5G SSID", s["ssid5g"]),
                        ("在线设备", s["online"] + " 台"),
                        ("连接状态", s["wanStatus"] == "Connected" ? "已连接" : s["wanStatus"])
                    ])

                    infoCard("SIM 卡", icon: "simcard", rows: [
                        ("运营商", s.carrierName),
                        ("本机号码", masked ? "••••••••" : s["phone"]),
                        ("IMSI", masked ? "••••••••" : s["imsi"]),
                        ("ICCID", masked ? "••••••••" : s["iccid"]),
                        ("IMEI", masked ? "••••••••" : s["imei"]),
                        ("注册状态", s["regstatus"] == "0" ? "已注册" : "未注册")
                    ])
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
            .background(GlassListBackground())
            .navigationTitle("参数")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        masked.toggle()
                    } label: {
                        Image(systemName: masked ? "eye.slash" : "eye")
                    }
                }
            }
        }
    }

    private var overviewCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("设备型号")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(s.deviceModel)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            Spacer()
            if let t = s.temperature {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("模组温度")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 3) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 13))
                        Text(String(format: "%.1f°C", t))
                            .font(.system(size: 19, weight: .bold))
                    }
                    .foregroundStyle(t >= 50 ? .red : (t >= 42 ? .orange : .green))
                }
            }
        }
        .padding(16)
        .glassCard(radius: 20, strong: true)
    }

    /// 三列网格信息卡（更紧凑，无需长列表滚动）
    private func infoCard(_ title: String, icon: String,
                          rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)],
                      alignment: .leading, spacing: 9) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.0)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(r.1.isEmpty || r.1 == "-" ? "--" : r.1)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .glassCard(radius: 18)
    }
}

// MARK: - 型号浮层

struct ModelSheet: View {
    let status: CpeStatus
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                row("型号", status["model"])
                row("厂商", status["vendor"])
                row("软件版本", status["swver"])
                row("硬件版本", status["hwver"])
                row("5G 模组", status["modem"])
                row("序列号", status["sn"])
                row("工作模式", status["workmode"])
            }
            .navigationTitle("设备信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v.isEmpty ? "--" : v).font(.system(size: 13, weight: .medium))
        }
        .font(.system(size: 13))
    }
}

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject var store: CpeStore
    @State private var showConn = false
    @AppStorage("appTheme") private var theme = "system"

    var body: some View {
        NavigationStack {
            List {
                // ── 连接状态 ──
                Section {
                    HStack(spacing: 11) {
                        Circle()
                            .fill(store.isLoggedIn ? Color.green : Color.red)
                            .frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.isLoggedIn ? "已连接" : "未连接")
                                .font(.system(size: 15, weight: .semibold))
                            Text(connSubtitle)
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("编辑") {
                            Haptic.light()
                            showConn = true
                        }
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.vertical, 2)
                }

                // ── 外观 ──
                Section {
                    Picker("主题", selection: $theme) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: theme) { newValue in
                        applyAppearance(newValue)
                    }
                } header: {
                    Text("外观")
                }

                // ── 刷新频率 ──
                Section {
                    Picker("刷新间隔", selection: Binding(
                        get: { store.refreshInterval },
                        set: { store.refreshInterval = $0; store.startPolling() }
                    )) {
                        Text("0.5s").tag(0.5)
                        Text("1s").tag(1.0)
                        Text("1.5s").tag(1.5)
                        Text("2s").tag(2.0)
                        Text("3s").tag(3.0)
                        Text("5s").tag(5.0)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("数据刷新")
                }

                // ── 显示 ──
                Section {
                    Toggle(isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "keepAwake") },
                        set: { v in
                            UserDefaults.standard.set(v, forKey: "keepAwake")
                            UIApplication.shared.isIdleTimerDisabled = v
                            Haptic.medium()
                            store.toast(v ? "屏幕保持常亮" : "已恢复自动锁屏", kind: .info)
                        }
                    )) {
                        Label("屏幕常亮", systemImage: "sun.max")
                    }
                } header: {
                    Text("显示")
                } footer: {
                    Text("分屏挂机看流量时建议开启，否则系统会自动锁屏暂停刷新。")
                }

                // ── 连接诊断 ──
                Section {
                    NavigationLink {
                        DiagView()
                            .environmentObject(store)
                    } label: {
                        Label("连接诊断", systemImage: "stethoscope")
                    }
                }

                // ── 关于 ──
                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("设备")
                        Spacer()
                        Text(store.status.deviceModel)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("关于")
                }

                // ── 退出 ──
                Section {
                    Button("退出登录", role: .destructive) {
                        Haptic.warning()
                        // 只退出会话，保留已记住的密码，下次免输入
                        store.isLoggedIn = false
                        store.stopPolling()
                    }
                }
            }
            .glassListStyle()
            .navigationTitle("设置")
            .sheet(isPresented: $showConn) {
                ConnEditor()
                    .environmentObject(store)
            }
            .onAppear { applyAppearance(theme) }
        }
    }

    /// 当前连接的设备信息
    /// 连接信息：优先用当前设备档案
    private var connSubtitle: String {
        if let p = store.activeProfile {
            return p.host + " · " + p.user
        }
        let cfg = Settings.load()
        return cfg.host + " · " + cfg.user
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(v) (\(b))"
    }

    private func applyAppearance(_ mode: String) {
        let scenes = UIApplication.shared.connectedScenes
        let style: UIUserInterfaceStyle
        switch mode {
        case "light": style = .light
        case "dark":  style = .dark
        default:      style = .unspecified
        }
        for s in scenes {
            guard let w = s as? UIWindowScene else { continue }
            for win in w.windows { win.overrideUserInterfaceStyle = style }
        }
    }
}

struct ConnEditor: View {
    @EnvironmentObject var store: CpeStore
    @Environment(\.dismiss) var dismiss
    @State private var host = Settings.load().host
    @State private var user = Settings.load().user
    @State private var password = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("设备地址") {
                    TextField("192.168.8.1", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("账号") {
                    TextField("superadmin", text: $user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码（留空则不修改）", text: $password)
                }
                Section {
                    Button {
                        Haptic.medium()
                        Task {
                            busy = true
                            _ = await store.login(
                                host: host, user: user,
                                password: password.isEmpty ? Settings.load().password : password)
                            busy = false
                            if store.isLoggedIn { dismiss() }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if busy { ProgressView().padding(.trailing, 6) }
                            Text(busy ? "测试中…" : "测试并保存")
                            Spacer()
                        }
                    }
                    .disabled(busy)
                }
            }
            .navigationTitle("连接设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}






// MARK: - 连接诊断

struct DiagView: View {
    @EnvironmentObject var store: CpeStore
    @State private var lines: [String] = []
    @State private var running = false
    @State private var vendor: CpeVendor = .fiberhome
    @State private var host = ""
    @State private var user = ""
    @State private var pass = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // 自动扫描
                Button {
                    Task {
                        running = true
                        lines = ["正在扫描局域网…"]
                        let results = await CpeDetector.detect()
                        lines = []
                        if results.isEmpty {
                            lines.append("✗ 未发现可识别的 CPE")
                        } else {
                            for r in results {
                                lines.append("✓ \(r.vendor.displayName) · \(r.host) · \(r.evidence)")
                            }
                            vendor = results[0].vendor
                            host = results[0].host
                            user = results[0].vendor.defaultUser
                        }
                        running = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if running { ProgressView().scaleEffect(0.7) }
                        Text(running ? "扫描中…" : "扫描局域网设备").font(.system(size: 13))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.1)))
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(running)

                // 厂商选择
                Picker("厂商", selection: $vendor) {
                    ForEach(CpeVendor.allCases, id: \.self) { v in
                        Text(v.displayName).tag(v)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: vendor) { v in
                    host = v.defaultHost
                    user = v.defaultUser
                    Haptic.selection()
                }

                VStack(spacing: 8) {
                    TextField("设备地址", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.background))
                    TextField("账号", text: $user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.background))
                    SecureField("密码", text: $pass)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.background))
                }

                Button {
                    Task { await run() }
                } label: {
                    HStack {
                        if running { ProgressView().padding(.trailing, 6) }
                        Text(running ? "检测中…" : "开始检测").bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue))
                    .foregroundStyle(.white)
                }
                .disabled(running)

                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    Text(l)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(l.hasPrefix("✗") ? Color.red : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
        }
        .navigationTitle("连接诊断")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 默认带出当前设备的信息
            if let p = store.activeProfile {
                vendor = p.vendor
                host = p.host
                user = p.user
                pass = p.password
            } else {
                vendor = .fiberhome
                host = CpeVendor.fiberhome.defaultHost
                user = CpeVendor.fiberhome.defaultUser
            }
        }
    }

    private func run() async {
        running = true
        lines = []
        CpeNativeAPI.trace = []

        let h = host.trimmingCharacters(in: .whitespaces)
        let u = user.trimmingCharacters(in: .whitespaces)

        lines.append("厂商: \(vendor.displayName)")
        lines.append("地址: \(h)")
        lines.append("账号: \(u)")
        lines.append("密码: \(pass.isEmpty ? "空" : "已填 \(pass.count) 位")")
        lines.append("")

        guard !h.isEmpty, !u.isEmpty, !pass.isEmpty else {
            lines.append("✗ 请完整填写地址、账号、密码")
            running = false
            return
        }

        if vendor == .oppo {
            await runOppo(host: h, user: u, pass: pass)
        } else {
            await runFiberhome(host: h, user: u, pass: pass)
        }
        running = false
    }

    // MARK: 烽火：原生 API

    private func runFiberhome(host: String, user: String, pass: String) async {
        let st = CpeNativeAPI.shared.selfTest()
        lines.append(st.ok ? "✓ \(st.detail)" : "✗ \(st.detail)")
        lines.append("")

        CpeNativeAPI.shared.configure(host: host, user: user, pass: pass)
        do {
            try await CpeNativeAPI.shared.login()
            lines.append("✓ 登录成功")
            do {
                let v = try await CpeNativeAPI.shared.values(CpeNode.overview)
                lines.append(v.isEmpty ? "✗ 取值返回空" : "✓ 取值 \(v.count) 项")
                if let m = v["model"] { lines.append("  型号: \(m)") }
                if let r = v["rsrp"] { lines.append("  RSRP: \(r)") }
            } catch {
                lines.append("✗ 取值失败: \(error.localizedDescription)")
            }
        } catch {
            let m = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lines.append("✗ 登录失败: \(m)")
        }

        if !CpeNativeAPI.trace.isEmpty {
            lines.append("")
            lines.append("— 原始响应 —")
            for t in CpeNativeAPI.trace { lines.append(t) }
        }
    }

    // MARK: OPPO：WebView 桥接

    private func runOppo(host: String, user: String, pass: String) async {
        lines.append("方式: WebView 桥接")
        lines.append("")

        // 第一步：JS 引擎自检
        let js = await OppoBridge.shared.selfTest()
        lines.append(js)
        if js.hasPrefix("X") {
            lines.append("")
            lines.append("JS 引擎不可用，WebView 方案无法工作")
            return
        }
        lines.append("")

        let ok = await OppoBridge.shared.login(host: host, user: user, password: pass)
        if !ok {
            lines.append("✗ 登录失败: \(OppoBridge.shared.lastError ?? "未知")")
            return
        }
        lines.append("✓ 登录成功")

        // 取页面数据
        for attempt in 1...3 {
            let d = await OppoBridge.shared.fetchDashboard()
            if !d.isEmpty {
                lines.append("✓ 页面数据 \(d.count) 项")
                if let m = d["model"] { lines.append("  型号: \(m)") }
                if let b = d["band"] { lines.append("  频段: \(b)") }
                if let p = d["pci"] { lines.append("  PCI: \(p)") }
                if let r = d["rsrp"] { lines.append("  RSRP: \(r)") }
                if let s = d["speedTx"] { lines.append("  上行: \(s)") }
                break
            }
            if attempt == 3 { lines.append("✗ 页面数据为空") }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }

        // 取流量接口
        let st = await OppoBridge.shared.fetchStats()
        if let rx = st["rx"], let tx = st["tx"] {
            lines.append("✓ 流量接口")
            lines.append("  下行: \(rx) 字节")
            lines.append("  上行: \(tx) 字节")
            if let rr = st["rateRx"] { lines.append("  实时下行: \(rr) B/s") }
            if let rt = st["rateTx"] { lines.append("  实时上行: \(rt) B/s") }
        } else {
            lines.append("✗ 流量接口无数据")
        }

        // 桥接日志
        if !OppoBridge.shared.trace.isEmpty {
            lines.append("")
            lines.append("— 桥接日志 —")
            for t in OppoBridge.shared.trace { lines.append(t) }
        }
    }
}

