import SwiftUI
import UIKit

import SwiftUI

// MARK: - 登录

struct LoginView: View {
    @EnvironmentObject var store: CpeStore
    @State private var host = Settings.load().host
    @State private var user = Settings.load().user
    @State private var password = ""
    @State private var showPassword = false
    @State private var busy = false
    @State private var remember = !Settings.load().password.isEmpty
    @State private var autoLogin = UserDefaults.standard.bool(forKey: "autoLogin")
    @State private var showLog = false
    @FocusState private var focus: Field?

    private enum Field { case host, user, pass }

    var body: some View {
        NavigationStack {
            ZStack {
                // 浅色渐变背景
                LinearGradient(
                    colors: [
                        Color(red: 0.93, green: 0.95, blue: 1.0),
                        Color(red: 0.96, green: 0.97, blue: 1.0),
                        Color(red: 0.94, green: 0.96, blue: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 56)

                        // 标题（去掉图标与副标题）
                        Text("FiberHome Manager")
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundStyle(Color(white: 0.08))
                            .padding(.top, 70)

                        // 错误提示
                        if let err = store.errorText, !err.isEmpty {
                            errorBanner(err)
                                .padding(.top, 20)
                        }

                        // 表单卡片
                        formCard
                            .padding(.top, 26)

                        // 底部说明
                        Text("请确保手机已连接该路由器的 Wi-Fi，密码仅保存在本机。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(white: 0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.top, 18)

                        // 日志
                        logSection
                            .padding(.top, 24)

                        Spacer().frame(height: 30)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: - 表单卡片

    private var formCard: some View {
        VStack(spacing: 14) {
            // 路由器
            inputRow(icon: nil, label: "路由器", text: $host,
                     placeholder: "192.168.8.1", field: .host,
                     keyboard: .URL)

            // 账号
            // 账号：为空时显示极淡的默认账号提示（不抢眼，忘记时可参考）
            HStack(spacing: 10) {
                Text("账号")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(white: 0.5))
                    .frame(width: 52, alignment: .leading)

                ZStack(alignment: .leading) {
                    if user.isEmpty {
                        Text("默认 superadmin / admin")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(white: 0.78))   // 极淡
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $user)
                        .font(.system(size: 16))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .user)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(fieldBackground)
            .onChange(of: user) { newValue in
                // 账号被删空时，立即收起明文密码
                if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    showPassword = false
                }
            }

            // 密码
            HStack(spacing: 10) {
                Text("密码")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(white: 0.5))
                    .frame(width: 52, alignment: .leading)

                Group {
                    if showPassword {
                        TextField("请输入密码", text: $password)
                    } else {
                        SecureField("请输入密码", text: $password)
                    }
                }
                .font(.system(size: 16))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .pass)

                // 一键清空（有内容时才显示）
                if !password.isEmpty {
                    Button {
                        password = ""
                        showPassword = false      // 清空后收起明文
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(white: 0.72))
                    }
                    .transition(.opacity)
                }

                // 眼睛：账号为空时禁用（无从校验归属，避免误展示）
                let canReveal = !user.trimmingCharacters(in: .whitespaces).isEmpty
                Button {
                    guard canReveal else { return }
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 15))
                        .foregroundStyle(canReveal ? Color(white: 0.6)
                                                   : Color(white: 0.85))
                }
                .disabled(!canReveal)
                .animation(.easeInOut(duration: 0.2), value: password.isEmpty)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(fieldBackground)

            // 开关
            VStack(spacing: 0) {
                switchRow("记住密码", isOn: $remember)
                switchRow("自动登录", isOn: $autoLogin)
            }
            .padding(.top, 2)

            // 连接按钮
            Button {
                Task { await doLogin() }
            } label: {
                HStack(spacing: 8) {
                    if busy {
                        ProgressView()
                            .tint(Color(white: 0.25))
                    }
                    Text(busy ? "正在连接…" : "连接路由器")
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(Color(white: 0.15))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .fill(Color.white.opacity(0.75))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .strokeBorder(Color(white: 0.85), lineWidth: 1)
                )
            }
            .disabled(busy)
            .padding(.top, 8)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.2)
        )
        .shadow(color: Color(red: 0.6, green: 0.67, blue: 0.95).opacity(0.12),
                radius: 24, x: 0, y: 10)
        .padding(.horizontal, 20)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.72))
    }

    private func inputRow(icon: String?, label: String, text: Binding<String>,
                          placeholder: String, field: Field,
                          keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Color(white: 0.5))
                .frame(width: 52, alignment: .leading)

            TextField(placeholder, text: text)
                .font(.system(size: 16))
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: field)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(fieldBackground)
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Color(white: 0.15))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color(red: 0.35, green: 0.78, blue: 0.42))
        }
        .padding(.horizontal, 6)
        .frame(height: 50)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.9, green: 0.3, blue: 0.3))
            Text(msg)
                .font(.system(size: 12.5))
                .foregroundStyle(Color(red: 0.8, green: 0.2, blue: 0.2))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 1.0, green: 0.93, blue: 0.93))
        )
        .padding(.horizontal, 20)
    }

    // MARK: - 日志

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showLog.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: showLog ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text("详细日志")
                        .font(.system(size: 12.5))
                }
                .foregroundStyle(Color(white: 0.45))
            }
            .padding(.leading, 24)

            if showLog {
                VStack(alignment: .leading, spacing: 4) {
                    if CpeNativeAPI.trace.isEmpty {
                        Text("暂无日志")
                            .foregroundStyle(Color(white: 0.6))
                    } else {
                        ForEach(Array(CpeNativeAPI.trace.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .foregroundStyle(Color(white: 0.35))
                        }
                    }
                }
                .font(.system(size: 10.5, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.5))
                )
                .padding(.horizontal, 24)
            }

            // 诊断入口
            NavigationLink {
                DiagView().environmentObject(store)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 11))
                    Text("连接诊断")
                        .font(.system(size: 12.5))
                }
                .foregroundStyle(Color(red: 0.35, green: 0.5, blue: 0.95))
            }
            .padding(.leading, 24)
        }
    }

    // MARK: - 登录

    private func doLogin() async {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { store.errorText = "请填写路由器地址"; return }
        guard !u.isEmpty else { store.errorText = "请填写账号"; return }
        guard !password.isEmpty else { store.errorText = "请输入密码"; return }

        busy = true
        store.errorText = nil
        let ok = await store.login(host: h, user: u, password: password)
        busy = false
        if ok {
            // 记住密码：写入钥匙串；否则清掉
            if remember {
                Settings(host: h, user: u, password: password).save()
                UserDefaults.standard.set(autoLogin, forKey: "autoLogin")
            } else {
                Settings.clearPassword()
                UserDefaults.standard.set(false, forKey: "autoLogin")
            }
            if autoLogin {
                UserDefaults.standard.set(true, forKey: "autoLogin")
            }
            store.startPolling()
        }
    }
}

// MARK: - 控制

struct ControlView: View {
    @EnvironmentObject var store: CpeStore
    @State private var pendingToggle: (node: String, on: Bool, label: String)?
    @State private var showReboot = false
    /// 本地覆盖：点击后立即反映，避免开关弹回
    @State private var localOverride: [String: Bool] = [:]
    @State private var busyNode: String?

    var body: some View {
        NavigationStack {
            WideAdapter {
            List {
                Section("网络开关") {
                    toggleRow("飞行模式", "关闭所有无线收发",
                              CpeNode.netSet + "airplan_on", "airplane")
                    toggleRow("数据漫游", "允许漫游网络接入",
                              CpeNode.netSet + "RoamingEnable", "roaming")
                    toggleRow("VoLTE", "高清语音通话",
                              CpeNode.netSet + "volte_switch", "volte")
                    toggleRow("载波聚合", "多频段叠加提速",
                              "X_FH_MobileNetwork.NetworkInfo.CaEnable", "ca")
                }

                Section("设备操作") {
                    Button {
                        showReboot = true
                    } label: {
                        Label("重启设备", systemImage: "power")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("控制")
            }
            .alert("确认操作", isPresented: Binding(
                get: { pendingToggle != nil },
                set: { if !$0 { pendingToggle = nil } }
            )) {
                Button("取消", role: .cancel) { pendingToggle = nil }
                Button("确定") {
                    guard let p = pendingToggle else { return }
                    pendingToggle = nil
                    busyNode = p.node
                    localOverride[p.node] = p.on          // 立即反映
                    Task {
                        let ok = await store.setToggle(node: p.node, on: p.on)
                        busyNode = nil
                        if !ok {
                            localOverride.removeValue(forKey: p.node)   // 失败回滚
                            store.toast("设置失败，请重试")
                        } else if let e = store.errorText, !e.isEmpty {
                            store.toast(e)
                        } else {
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            localOverride.removeValue(forKey: p.node)   // 以服务器为准
                        }
                    }
                }
            } message: {
                if let p = pendingToggle {
                    Text("确定要\(p.on ? "开启" : "关闭")\(p.label)吗？")
                }
            }
            .alert("重启设备", isPresented: $showReboot) {
                Button("取消", role: .cancel) { }
                Button("重启", role: .destructive) {
                    Task { _ = await store.reboot() }
                }
            } message: {
                Text("重启期间所有设备将断开网络，约需 1 分钟恢复。")
            }
        }
    }

    private func toggleRow(_ title: String, _ sub: String,
                           _ node: String, _ key: String) -> some View {
        let serverOn = store.status[key] == "1"
        let isOn = localOverride[node] ?? serverOn
        return Toggle(isOn: Binding(
            get: { isOn },
            set: { newValue in
                pendingToggle = (node, newValue, title)
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(sub).font(.system(size: 11.5)).foregroundStyle(.secondary)
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
            WideAdapter {
            List {
                Section("CPE 信息") {
                    row("型号", s["model"])
                    row("序列号", masked ? "••••••••" : s["sn"])
                    row("厂商", s["vendor"])
                    row("工作模式", s["workmode"])
                    row("软件版本", s["swver"])
                    row("硬件版本", s["hwver"])
                    row("模组版本", s["modem"])
                    if let t = s.temperature {
                        row("模组温度", String(format: "%.1f ℃", t))
                    }
                }

                Section("网络") {
                    row("WAN IP", s["wanIP"])
                    row("LAN IP", s["lanIP"])
                    row("2.4G SSID", s["ssid24"])
                    row("5G SSID", s["ssid5g"])
                    row("在线设备", s["online"])
                    row("连接状态", s["wanStatus"] == "Connected" ? "已连接" : s["wanStatus"])
                }

                Section("SIM 卡") {
                    row("运营商", s.carrierName)
                    row("本机号码", masked ? "••••••••" : s["phone"])
                    row("IMSI", masked ? "••••••••" : s["imsi"])
                    row("ICCID", masked ? "••••••••" : s["iccid"])
                    row("IMEI", masked ? "••••••••" : s["imei"])
                    row("注册状态", s["regstatus"] == "0" ? "已注册" : "未注册")
                }
            }
            .navigationTitle("参数")
            }
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

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v.isEmpty ? "--" : v)
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 14))
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
                            Text(Settings.load().host + " · " + Settings.load().user)
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("编辑") { showConn = true }
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
                        Text(store.status["model"].isEmpty ? "--" : store.status["model"])
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("关于")
                }

                // ── 退出 ──
                Section {
                    Button("退出登录", role: .destructive) {
                        Settings.clearPassword()
                        store.isLoggedIn = false
                        store.stopPolling()
                    }
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showConn) {
                ConnEditor()
                    .environmentObject(store)
            }
            .onAppear { applyAppearance(theme) }
        }
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
    @State private var host = Settings.load().host
    @State private var user = Settings.load().user
    @State private var pass = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 8) {
                    TextField("设备地址", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.background))
                    TextField("账号", text: $user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.background))
                    SecureField(Settings.load().password.isEmpty ? "密码" : "已保存，留空则沿用", text: $pass)
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
    }

    private func run() async {
        running = true
        lines = []
        CpeNativeAPI.trace = []

        let h = host.trimmingCharacters(in: .whitespaces)
        let u = user.trimmingCharacters(in: .whitespaces)
        let p = pass.isEmpty ? Settings.load().password : pass

        // 0. 加密自检
        let st = CpeNativeAPI.shared.selfTest()
        lines.append(st.ok ? "✓ \(st.detail)" : "✗ \(st.detail)")
        lines.append("")

        lines.append("地址: \(h)")
        lines.append("账号: \(u)")
        lines.append("密码: \(p.isEmpty ? "空" : "已填 \(p.count) 位")")
        lines.append("")

        guard !p.isEmpty else {
            lines.append("✗ 密码为空，无法测试")
            running = false
            return
        }

        CpeNativeAPI.shared.configure(host: h, user: u, pass: p)
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
        running = false
    }
}
