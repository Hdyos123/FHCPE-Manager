import SwiftUI

// MARK: - 登录（选择厂商并连接）

struct LoginView: View {
    @EnvironmentObject var store: CpeStore
    @Environment(\.colorScheme) private var scheme

    @State private var vendor: CpeVendor?
    @State private var host = ""
    @State private var user = ""
    @State private var password = ""
    @State private var showVendorPicker = false
    @State private var showPassword = false
    @State private var busy = false
    @State private var remember = true
    @State private var autoLogin = true
    @State private var logs: [String] = []
    @State private var showLogs = true
    @State private var detecting = false
    @State private var hasAutoDetected = false
    @FocusState private var focus: Field?

    private enum Field { case host, user, pass }

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        formCard
                            .padding(.top, 22)
                        FooterLog(logs: logs, expanded: $showLogs)
                            .padding(.top, 20)
                        Spacer().frame(height: 30)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarHidden(true)
        }
        .task {
            guard !hasAutoDetected else { return }
            hasAutoDetected = true

            // 已有保存的设备，直接带出来，不扫描（省时间）
            if let p = ProfileStore.active ?? ProfileStore.loadAll().first {
                vendor = p.vendor
                host = p.host
                user = p.user
                password = p.password
                addLog("已载入上次设备：\(p.vendor.displayName) @ \(p.host)")
                if !p.password.isEmpty { focus = .pass }
                return
            }

            // 没有保存过，自动扫描
            try? await Task.sleep(nanoseconds: 500_000_000)
            await autoDetect()
        }
        .sheet(isPresented: $showVendorPicker) {
            VendorPicker(current: vendor, onSelect: selectVendor)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: 背景

    private var background: some View {
        Group {
            if scheme == .dark {
                LinearGradient(colors: [Color(red: 0.06, green: 0.07, blue: 0.12),
                                        Color(red: 0.09, green: 0.11, blue: 0.18)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [Color(red: 0.93, green: 0.95, blue: 1.0),
                                        Color(red: 0.97, green: 0.98, blue: 1.0)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }

    // MARK: 标题

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("连接你的设备")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.primary)

            Text("选择厂商后连接当前局域网内的设备")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 表单

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // WiFi 提示（移到上方）
            HStack(spacing: 6) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text("请先连接设备的 Wi-Fi，再开始管理")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)

            // 厂商
            VStack(alignment: .leading, spacing: 8) {
                Text("设备厂商")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))

                Button {
                    Haptic.light()
                    showVendorPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Group {
                            if let v = vendor {
                                Image(v.logoAsset).resizable().scaledToFit()
                            } else {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.blue.opacity(0.15))
                                    .overlay(
                                        Image(systemName: "cube.box")
                                            .font(.system(size: 17, weight: .medium))
                                            .foregroundStyle(.blue)
                                    )
                            }
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vendor?.displayName ?? "选择设备厂商")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(vendor?.hint ?? "点击选择设备厂商")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    .padding(12)
                    .background(fieldBg)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 自动检测按钮
                Button {
                    Task { await autoDetect() }
                } label: {
                    HStack(spacing: 6) {
                        if detecting {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text(detecting ? "正在扫描局域网…" : (vendor == nil ? "自动检测设备" : "重新检测"))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.blue.opacity(scheme == .dark ? 0.14 : 0.09))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(detecting)
            }

            fieldBlock("管理地址", placeholder: "请先选择设备厂商",
                       text: $host, field: .host, disabled: vendor == nil)

            fieldBlock("管理员账号", placeholder: "请先选择设备厂商",
                       text: $user, field: .user, disabled: vendor == nil)

            // 密码
            VStack(alignment: .leading, spacing: 8) {
                Text("管理员密码")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))

                HStack(spacing: 8) {
                    Group {
                        if showPassword {
                            TextField("", text: $password,
                                      prompt: pwdPrompt)
                        } else {
                            SecureField("", text: $password,
                                        prompt: pwdPrompt)
                        }
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .pass)
                    .submitLabel(.go)
                    .onSubmit {
                        if canConnect && !busy {
                            Haptic.medium()
                            Task { await doConnect() }
                        }
                    }
                    .disabled(vendor == nil)

                    if !password.isEmpty {
                        Button {
                            Haptic.light()
                            password = ""
                            showPassword = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                    }

                    Button {
                        guard canReveal else { return }
                        Haptic.selection()
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 15))
                            .foregroundStyle(canReveal ? Color.secondary : Color.secondary.opacity(0.35))
                    }
                    .disabled(!canReveal)
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(fieldBg)
            }

            // 开关
            HStack {
                toggleItem("记住密码", isOn: $remember)
                toggleItem("自动登录", isOn: $autoLogin)
            }
            .padding(.top, 2)

            // 连接按钮
            Button {
                Task { await doConnect() }
            } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white).scaleEffect(0.85) }
                    Text(busy ? "正在连接…" : "连接并登录")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(canConnect ? Color.blue : Color.blue.opacity(0.35))
                )
            }
            .disabled(!canConnect || busy)
            .padding(.top, 4)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.12 : 0.06), lineWidth: 1)
        )
    }

    private var pwdPrompt: Text {
        Text(vendor == nil ? "请先选择设备厂商" : "请输入密码")
            .foregroundColor(.secondary.opacity(0.6))
    }

    private var fieldBg: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(scheme == .dark ? Color.white.opacity(0.07) : Color.primary.opacity(0.05))
    }

    private func fieldBlock(_ label: String, placeholder: String,
                            text: Binding<String>, field: Field,
                            disabled: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))

            TextField("", text: text,
                      prompt: Text(placeholder).foregroundColor(.secondary.opacity(0.6)))
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .focused($focus, equals: field)
                .submitLabel(.next)
                .onSubmit {
                    switch field {
                    case .host: focus = .user
                    case .user: focus = .pass
                    case .pass: focus = nil
                    }
                }
                .disabled(disabled)
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(fieldBg)
        }
    }

    private func toggleItem(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.green)
                .scaleEffect(0.9)
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    // MARK: 逻辑

    private var canConnect: Bool {
        vendor != nil && !host.isEmpty && !user.isEmpty && !password.isEmpty
    }

    private var canReveal: Bool { !user.trimmingCharacters(in: .whitespaces).isEmpty }

    /// 自动扫描局域网并识别设备
    private func autoDetect() async {
        guard !detecting else { return }
        detecting = true
        addLog("开始扫描局域网…")

        let results = await CpeDetector.detect()
        detecting = false

        guard let first = results.first else {
            addLog("✗ 未发现可识别的 CPE 设备")
            addLog("  请确认已连接设备 Wi-Fi")
            return
        }

        // 找到就自动填充
        vendor = first.vendor
        host = first.host
        user = first.vendor.defaultUser
        Haptic.success()

        addLog("✓ 发现 \(first.vendor.displayName)：\(first.host)（\(first.evidence)）")
        if results.count > 1 {
            addLog("  还发现 \(results.count - 1) 台，已选用第一台")
        }
        addLog("  已自动填入地址与账号，请输入密码")

        // 有保存的密码就带出来
        if let saved = ProfileStore.loadAll().first(where: {
            $0.vendor == first.vendor && $0.host == first.host && !$0.password.isEmpty
        }) {
            password = saved.password
            addLog("  已填入上次保存的密码")
        }

        focus = .pass
    }

    private func selectVendor(_ v: CpeVendor) {
        vendor = v
        host = v.defaultHost
        user = v.defaultUser
        Haptic.selection()
        addLog("已选择厂商：\(v.displayName)（\(v.defaultHost) / \(v.defaultUser)）")
    }

    private func addLog(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        logs.append("[\(f.string(from: Date()))] \(s)")
        if logs.count > 60 { logs.removeFirst() }
    }

    private func doConnect() async {
        guard let v = vendor else {
            addLog("✗ 请先选择设备厂商")
            store.errorText = "请先选择设备厂商"
            return
        }
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, !u.isEmpty, !password.isEmpty else {
            addLog("✗ 请完整填写连接信息")
            store.errorText = "请完整填写连接信息"
            return
        }

        busy = true
        store.errorText = nil
        addLog("开始连接 \(v.displayName) @ \(h)")

        var p = CpeProfile.make(vendor: v)
        p.host = h
        p.user = u
        p.password = password
        p.name = v.displayName

        let ok = await store.login(profile: p)
        busy = false

        if ok {
            addLog("✓ 连接成功")
            if remember {
                ProfileStore.upsert(p)
                ProfileStore.activeID = p.id
                UserDefaults.standard.set(autoLogin, forKey: "autoLogin")
            }
            store.startPolling()
        } else {
            addLog("✗ " + (store.errorText ?? "连接失败"))
            // OPPO 桥接日志也贴出来
            if v == .oppo {
                for t in OppoBridge.shared.trace { addLog("  " + t) }
            }
        }
    }
}

// MARK: - 底部诊断日志

struct FooterLog: View {
    let logs: [String]
    @Binding var expanded: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptic.light()
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 11))
                    Text("诊断日志")
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 3) {
                    if logs.isEmpty {
                        Text("暂无日志，连接后会在这里显示过程")
                            .foregroundStyle(.secondary.opacity(0.6))
                    } else {
                        ForEach(Array(logs.enumerated()), id: \.offset) { _, l in
                            Text(l)
                                .foregroundStyle(l.contains("✗") ? Color.red : Color.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .font(.system(size: 10.5, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.05) : Color.primary.opacity(0.04))
                )
            }
        }
    }
}

// MARK: - 厂商选择

struct VendorPicker: View {
    let current: CpeVendor?
    let onSelect: (CpeVendor) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("选择设备厂商")
                        .font(.system(size: 19, weight: .bold))
                    Text("地址与密码分别保存")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 16)

            // 厂商列表（用 Button 而非 List，避免点击失效）
            VStack(spacing: 10) {
                ForEach(CpeVendor.allCases, id: \.self) { v in
                    Button {
                        Haptic.medium()
                        onSelect(v)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(v.logoAsset)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.displayName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(v.hint)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if current == v {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.blue)
                            } else {
                                Image(systemName: "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.secondary.opacity(0.25))
                            }
                        }
                        .padding(13)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(current == v ? Color.blue.opacity(0.5) : Color.clear,
                                              lineWidth: 1.5)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color(.systemGroupedBackground))
    }
}
