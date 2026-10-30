import SwiftUI

// MARK: - 登录

struct LoginView: View {
    @EnvironmentObject var store: CpeStore
    @State private var host = Settings.load().host
    @State private var user = Settings.load().user
    @State private var password = ""
    @State private var showPassword = false
    @State private var busy = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    Spacer().frame(height: 40)

                    VStack(spacing: 10) {
                        Image(systemName: "wifi.router.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(LinearGradient(colors: [.blue, .cyan],
                                                            startPoint: .top, endPoint: .bottom))
                        Text("CPE 助手").font(.system(size: 26, weight: .bold))
                        Text("连接你的 5G 路由器")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 10)

                    if let err = store.errorText, !err.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(err).font(.system(size: 12.5))
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            if err.contains("连接") || err.contains("超时") || err.contains("脚本") {
                                Text("排查：① 手机需连 CPE 的 Wi-Fi（不是蜂窝）② 允许「本地网络」权限 ③ 地址填 192.168.8.1")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.1)))
                    }

                    VStack(spacing: 0) {
                        field("设备地址", text: $host, placeholder: "192.168.8.1",
                              keyboard: .URL, id: "host")
                        Divider().padding(.leading, 14)
                        field("账号", text: $user, placeholder: "superadmin", id: "user")
                        Divider().padding(.leading, 14)
                        passwordField
                    }
                    .background(RoundedRectangle(cornerRadius: 16).fill(.background))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))

                    Button {
                        Task {
                            // 前置校验，避免提交空值导致设备返回 4|0
                            let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
                            let u = user.trimmingCharacters(in: .whitespacesAndNewlines)
                            if h.isEmpty { store.errorText = "请填写设备地址"; return }
                            if u.isEmpty { store.errorText = "请填写账号"; return }
                            if password.isEmpty {
                                let saved = Settings.load().password
                                if saved.isEmpty {
                                    store.errorText = "请输入密码"
                                    return
                                }
                            }
                            busy = true
                            store.errorText = nil
                            let pwd = password.isEmpty ? Settings.load().password : password
                            let ok = await store.login(host: h, user: u, password: pwd)
                            busy = false
                            if ok { store.startPolling() }
                        }
                    } label: {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? "正在连接…" : "测试并保存")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 15)
                            .fill(LinearGradient(colors: [.blue, .blue.opacity(0.85)],
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing)))
                    }
                    .disabled(busy || password.isEmpty)

                    VStack(spacing: 6) {
                        Label("请确保手机已连接该 CPE 的 Wi-Fi", systemImage: "wifi")
                        Label("密码保存在系统钥匙串，不会明文存储", systemImage: "lock.shield")
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 22)
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String,
                       keyboard: UIKeyboardType = .default, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 16))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("密码").font(.system(size: 11.5)).foregroundStyle(.secondary)
            HStack {
                if showPassword {
                    TextField("设备管理密码", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField(Settings.load().password.isEmpty ? "设备管理密码" : "已保存，留空则沿用", text: $password)
                }
                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 16))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - 控制

struct ControlView: View {
    @EnvironmentObject var store: CpeStore
    @State private var pendingToggle: (node: String, on: Bool, label: String)?
    @State private var showReboot = false

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
                    if let p = pendingToggle {
                        Task { _ = await store.setToggle(node: p.node, on: p.on) }
                    }
                    pendingToggle = nil
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
        let isOn = store.status[key] == "1"
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Circle()
                            .fill(store.isLoggedIn ? .green : .red)
                            .frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(store.isLoggedIn ? "已连接" : "未连接")
                                .font(.system(size: 14, weight: .semibold))
                            Text(Settings.load().host)
                                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("编辑") { showConn = true }
                            .font(.system(size: 13, weight: .semibold))
                    }
                }

                Section("刷新频率") {
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
                }

                Section("诊断") {
                    NavigationLink {
                        DiagView()
                    } label: {
                        Label("连接诊断", systemImage: "stethoscope")
                    }
                }

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
                    .presentationDetents([.medium])
            }
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if running {
                        ProgressView("检测中…").padding()
                    }
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                        Text(l)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(l.hasPrefix("✗") ? .red : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
            }
            .navigationTitle("连接诊断")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("开始") { Task { await run() } }
                        .disabled(running)
                }
            }
            .task { await run() }
        }
    }

    private func run() async {
        running = true
        lines = []
        let cfg = Settings.load()
        lines.append("地址: \(cfg.host)")
        lines.append("账号: \(cfg.user)")
        lines.append("密码: \(cfg.password.isEmpty ? "未保存" : "已保存")")
        lines.append("")

        // 1. 原生 API 登录
        CpeNativeAPI.shared.configure(host: cfg.host, user: cfg.user, pass: cfg.password)
        do {
            try await CpeNativeAPI.shared.login()
            lines.append("✓ 原生登录成功")
        } catch {
            let m = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lines.append("✗ 原生登录失败: \(m)")
        }

        // 2. 取数据
        do {
            let v = try await CpeNativeAPI.shared.values(CpeNode.overview)
            lines.append(v.isEmpty ? "✗ 原生取值返回空" : "✓ 原生取值 \(v.count) 项")
            if let rsrp = v["rsrp"] {
                lines.append("  信号 RSRP: \(rsrp)")
            }
            if let model = v["model"] {
                lines.append("  型号: \(model)")
            }
        } catch {
            lines.append("✗ 原生取值异常: \(error.localizedDescription)")
        }

        // 3. WebView 状态
        lines.append("")
        lines.append("WebView ready: \(CpeBridge.shared.ready ? "是" : "否")")
        if let e = CpeBridge.shared.lastError, !e.isEmpty {
            lines.append("WebView 错误: \(e)")
        }
        if !store.diagLog.isEmpty {
            lines.append("登录日志: \(store.diagLog)")
        }

        running = false
    }
}
