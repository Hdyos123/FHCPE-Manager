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
                            .padding(.top, 26)
                        footerHint
                            .padding(.top, 20)
                        logSection
                            .padding(.top, 22)
                        Spacer().frame(height: 30)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showVendorPicker) {
                VendorPicker(current: vendor) { v in
                    selectVendor(v)
                }
                .presentationDetents([.medium])
            }
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
            HStack(spacing: 7) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text("网络面板助手")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text("连接你的设备")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, 2)

            Text("选择厂商后连接当前局域网内的设备")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 表单

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: vendor?.icon ?? "cube.box")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(.blue)
                            )
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
                }
                .buttonStyle(.plain)
            }

            // 地址
            fieldBlock("管理地址", placeholder: "请先选择设备厂商",
                       text: $host, field: .host, disabled: vendor == nil)

            // 账号
            fieldBlock("管理员账号", placeholder: "admin",
                       text: $user, field: .user)

            // 密码
            VStack(alignment: .leading, spacing: 8) {
                Text("管理员密码")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))

                HStack(spacing: 8) {
                    Group {
                        if showPassword {
                            TextField("", text: $password,
                                      prompt: Text("请先选择设备厂商").foregroundColor(.secondary.opacity(0.6)))
                        } else {
                            SecureField("", text: $password,
                                        prompt: Text("请先选择设备厂商").foregroundColor(.secondary.opacity(0.6)))
                        }
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .pass)

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

            // 开关行
            HStack {
                toggleItem("记住密码", isOn: $remember)
                toggleItem("自动登录", isOn: $autoLogin)
            }
            .padding(.top, 2)

            Text("管理员凭据只保存于本机，不会上传服务器")
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.85))

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
            .padding(.top, 6)
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

    private var footerHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
            Text("请先连接设备的 Wi-Fi，再开始管理。")
                .font(.system(size: 12.5))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: 日志

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                DiagView().environmentObject(store)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 11))
                    Text("连接诊断")
                        .font(.system(size: 12.5))
                }
                .foregroundStyle(.blue.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: 逻辑

    private var canConnect: Bool {
        vendor != nil && !host.isEmpty && !user.isEmpty && !password.isEmpty
    }

    private var canReveal: Bool { !user.trimmingCharacters(in: .whitespaces).isEmpty }

    private func selectVendor(_ v: CpeVendor) {
        vendor = v
        showVendorPicker = false
        if host.isEmpty || CpeVendor.allCases.contains(where: { $0.defaultHost == host }) {
            host = v.defaultHost
        }
        if user.isEmpty || CpeVendor.allCases.contains(where: { $0.defaultUser == user }) {
            user = v.defaultUser
        }
        Haptic.selection()
    }

    private func doConnect() async {
        guard let v = vendor else { return }
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, !u.isEmpty, !password.isEmpty else {
            store.errorText = "请完整填写连接信息"
            return
        }

        busy = true
        store.errorText = nil

        var p = CpeProfile.make(vendor: v)
        p.host = h
        p.user = u
        p.password = password
        p.name = v.displayName

        let ok = await store.login(profile: p)
        busy = false

        if ok {
            if remember {
                ProfileStore.upsert(p)
                ProfileStore.activeID = p.id
                UserDefaults.standard.set(autoLogin, forKey: "autoLogin")
            }
            store.startPolling()
        }
    }
}

// MARK: - 厂商选择

struct VendorPicker: View {
    let current: CpeVendor?
    let onSelect: (CpeVendor) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(CpeVendor.allCases, id: \.self) { v in
                        Button {
                            onSelect(v)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.blue.opacity(0.14))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: v.icon)
                                            .font(.system(size: 17, weight: .medium))
                                            .foregroundStyle(.blue)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.displayName)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text(v.hint)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if current == v {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("选择 CPE 厂商，地址与密码分别保存")
                }
            }
            .navigationTitle("选择设备厂商")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
