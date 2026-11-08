import SwiftUI

/// 华为设置页
struct HuaweiSettingsView: View {
    @EnvironmentObject var store: CpeStore
    @AppStorage("autoLogin") private var autoLogin = true
    @AppStorage("savePassword") private var savePassword = true
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("bgTheme") private var bgTheme = 0
    @AppStorage("showSmsNotify") private var showSmsNotify = true

    @State private var showPwdSheet = false
    @State private var showLogoutConfirm = false
    @State private var showRebootConfirm = false
    @State private var busy = false

    private var s: CpeStatus { store.status }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                deviceHeader
                softwareCard
                accountCard
                appearanceCard
                wlanCard
                maintenanceCard
                rebootCard
                aboutCard
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 96)
        }
        .background(GlassListBackground())
        .sheet(isPresented: $showPwdSheet) { ChangePwdSheet() }
        .alert("退出登录？", isPresented: $showLogoutConfirm) {
            Button("退出", role: .destructive) { store.logout() }
            Button("取消", role: .cancel) {}
        }
        .alert("重启设备？", isPresented: $showRebootConfirm) {
            Button("重启", role: .destructive) { Task { _ = await store.reboot() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("设备会断开约 1 分钟，期间无法访问。")
        }
    }
}

// MARK: - 设备头卡
private extension HuaweiSettingsView {
    var deviceHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wifi.router")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("设备 · 在线")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                Spacer()
            }
            Text(s["model"].isEmpty ? "H153-381" : s["model"])
                .font(.system(size: 32, weight: .bold))
            Text("固件 \(s["swver"].isEmpty ? "--" : s["swver"])")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20)
    }
}

// MARK: - 软件交流
private extension HuaweiSettingsView {
    var softwareCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("软件交流")
                .font(.system(size: 16, weight: .bold))
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            HStack(spacing: 10) {
                iconCircle("bubble.left.and.bubble.right.fill", .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("QQ 交流群").font(.system(size: 13.5))
                    Text("群号 1107084040 · 点一下复制")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Haptic.success()
                    UIPasteboard.general.string = "1107084040"
                    store.toast("已复制群号")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc").font(.system(size: 10))
                        Text("复制").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color.blue.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)

            Divider().opacity(0.25).padding(.leading, 16)

            HStack(spacing: 10) {
                iconCircle("heart.fill", .pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("打赏支持").font(.system(size: 13.5))
                    Text("微信扫一扫，请作者喝杯咖啡")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
        }
        .glassCard(radius: 20)
    }

    func iconCircle(_ name: String, _ c: Color) -> some View {
        ZStack {
            Circle().fill(c.opacity(0.16)).frame(width: 30, height: 30)
            Image(systemName: name)
                .font(.system(size: 13))
                .foregroundStyle(c)
        }
    }
}

// MARK: - 账号与安全
private extension HuaweiSettingsView {
    var accountCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("账号与安全")
                .font(.system(size: 16, weight: .bold))
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            toggleRow("key.fill", .blue, "保存密码",
                      "密码存在系统钥匙串，关闭后需每次手动输入",
                      $savePassword)
            Divider().opacity(0.25).padding(.leading, 16)
            toggleRow("bolt.fill", .green, "自动登录",
                      "打开 App 时自动连接设备",
                      $autoLogin)
            Divider().opacity(0.25).padding(.leading, 16)

            Button {
                Haptic.light()
                showPwdSheet = true
            } label: {
                HStack(spacing: 10) {
                    iconCircle("key.horizontal.fill", .blue)
                    Text("修改管理员密码").font(.system(size: 13.5))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    Haptic.light()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "key.slash").font(.system(size: 13))
                        Text("忘记密码").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.red.opacity(0.10))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    Haptic.warning()
                    showLogoutConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 13))
                        Text("退出登录").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 1.0, green: 0.42, blue: 0.38))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.bottom, 16).padding(.top, 4)
        }
        .glassCard(radius: 20)
    }

    func toggleRow(_ icon: String, _ c: Color, _ title: String, _ sub: String,
                   _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            iconCircle(icon, c)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5))
                Text(sub).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(c)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - 外观与显示
private extension HuaweiSettingsView {
    var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("外观与显示")
                .font(.system(size: 16, weight: .bold))

            VStack(alignment: .leading, spacing: 6) {
                Text("外观").font(.system(size: 12.5))
                Text("跟随系统或固定深浅色")
                    .font(.system(size: 11)).foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    ForEach([("浅色", "light"), ("深色", "dark"), ("跟随系统", "system")], id: \.1) { t, v in
                        Button {
                            Haptic.light()
                            appearance = v
                        } label: {
                            Text(t)
                                .font(.system(size: 13, weight: appearance == v ? .semibold : .regular))
                                .foregroundStyle(appearance == v ? .white : Color.primary.opacity(0.7))
                                .frame(maxWidth: .infinity).frame(height: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(appearance == v ? Color.blue.opacity(0.85) : .clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }

            Divider().opacity(0.25)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("背景色").font(.system(size: 12.5))
                    Spacer()
                    Text("\(bgTheme + 1)/6")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        Haptic.light()
                        bgTheme = (bgTheme + 5) % 6
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    VStack(spacing: 6) {
                        HStack(spacing: 10) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(bgColor((bgTheme + i) % 6))
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle().stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                            }
                        }
                        Text(bgName(bgTheme))
                            .font(.system(size: 12, weight: .medium))
                    }

                    Spacer()

                    Button {
                        Haptic.light()
                        bgTheme = (bgTheme + 1) % 6
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .glassCard(radius: 20)
    }

    func bgColor(_ i: Int) -> Color {
        let cs: [Color] = [.blue, .green, .purple, .orange, .pink, .teal]
        return cs[i % 6]
    }

    func bgName(_ i: Int) -> String {
        let n = ["冰川蓝", "青草绿", "暮光紫", "落日橙", "樱花粉", "深海青"]
        return n[i % 6]
    }
}

// MARK: - WLAN
private extension HuaweiSettingsView {
    var wlanCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("WLAN 设置").font(.system(size: 16, weight: .bold))
                Text("2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            wlanRow("2.4GHz", "已关闭 · \(ssid("2.4G"))", on: false, idx: "1")
            Divider().opacity(0.25).padding(.leading, 16)
            wlanRow("5GHz_1", "已关闭 · \(ssid("5G"))", on: false, idx: "2")
        }
        .glassCard(radius: 20)
    }

    func ssid(_ band: String) -> String {
        let m = s["model"].isEmpty ? "H153-381" : s["model"]
        return band == "5G" ? "HUAWEI \(m)-5G" : "HUAWEI \(m)-2.4G"
    }

    func wlanRow(_ title: String, _ sub: String, on: Bool, idx: String) -> some View {
        HStack(spacing: 10) {
            iconCircle("wifi", .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 13.5))
                    Text("低频 36-64").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Text(sub).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: .constant(on))
                .labelsHidden()
                .disabled(true)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - 设备维护
private extension HuaweiSettingsView {
    var maintenanceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("设备维护")
                .font(.system(size: 16, weight: .bold))
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            simpleRow("arrow.triangle.2.circlepath", .green, "自动升级",
                      "发现新固件时自动下载并安装", trailing: nil)
            Divider().opacity(0.25).padding(.leading, 16)
            simpleRow("moon.zzz.fill", .teal, "闲时升级",
                      "允许服务器在空闲时段推送升级", trailing: nil)
            Divider().opacity(0.25).padding(.leading, 16)
            simpleRow("lightbulb.fill", .yellow, "信号灯定时关闭",
                      "", trailing: "未开启")
            Divider().opacity(0.25).padding(.leading, 16)
            simpleRow("clock.arrow.circlepath", .purple, "定时重启",
                      "", trailing: "未开启")
        }
        .glassCard(radius: 20)
    }

    func simpleRow(_ icon: String, _ c: Color, _ title: String,
                   _ sub: String, trailing: String?) -> some View {
        HStack(spacing: 10) {
            iconCircle(icon, c)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5))
                if !sub.isEmpty {
                    Text(sub).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let t = trailing {
                Text(t).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
}

// MARK: - 重启与恢复
private extension HuaweiSettingsView {
    var rebootCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("重启与恢复")
                .font(.system(size: 16, weight: .bold))

            Button {
                Haptic.light()
                Task {
                    busy = true
                    _ = await HuaweiBridge.shared.post("netMode", [:])
                    busy = false
                    store.toast("已请求重启网络", kind: .info)
                }
            } label: {
                Text("重启网络")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.blue.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)

            Button {
                Haptic.warning()
                showRebootConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13))
                    Text("重启设备").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.9))
                )
            }
            .buttonStyle(.plain)

            Button {
                Haptic.warning()
                Task {
                    let ok = await HuaweiAPI.shared.factoryReset()
                    store.toast(ok ? "已请求恢复出厂" : "操作失败",
                                kind: ok ? .info : .error)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 13))
                    Text("恢复出厂设置").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 1.0, green: 0.42, blue: 0.38))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .glassCard(radius: 20)
    }
}

// MARK: - 帮助与支持
private extension HuaweiSettingsView {
    var aboutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("帮助与支持")
                .font(.system(size: 16, weight: .bold))
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            Button {
                if let u = URL(string: "http://\(store.activeProfile?.host ?? "192.168.8.1")") {
                    UIApplication.shared.open(u)
                }
            } label: {
                HStack(spacing: 10) {
                    iconCircle("safari.fill", .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("在浏览器打开管理页").font(.system(size: 13.5))
                        Text("http://\(store.activeProfile?.host ?? "192.168.8.1")")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().opacity(0.25).padding(.leading, 16)

            HStack {
                Text("设备地址").font(.system(size: 12.5)).foregroundStyle(.secondary)
                Spacer()
                Text(store.activeProfile?.host ?? "--")
                    .font(.system(size: 12.5, design: .monospaced))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider().opacity(0.25).padding(.leading, 16)

            HStack {
                Text("本机 IP").font(.system(size: 12.5)).foregroundStyle(.secondary)
                Spacer()
                Text(localIP).font(.system(size: 12.5, design: .monospaced))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .padding(.bottom, 4)

            Text("CPE 管理 v1.8")
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .glassCard(radius: 20)
    }

    var localIP: String {
        var addr = ""
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return "--" }
        defer { freeifaddrs(ifaddr) }
        var ptr = first
        while true {
            let f = ptr.pointee
            if f.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: f.ifa_name)
                if name == "en0" || name == "en1" {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(f.ifa_addr, socklen_t(f.ifa_addr.pointee.sa_len),
                                &host, socklen_t(host.count), nil, 0,
                                NI_NUMERICHOST)
                    addr = String(cString: host)
                    break
                }
            }
            guard let n = f.ifa_next else { break }
            ptr = n
        }
        return addr.isEmpty ? "--" : addr
    }
}

// MARK: - 修改密码
struct ChangePwdSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var old = ""
    @State private var new1 = ""
    @State private var new2 = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("当前密码") {
                    SecureField("请输入当前密码", text: $old)
                }
                Section("新密码") {
                    SecureField("请输入新密码", text: $new1)
                    SecureField("再次输入", text: $new2)
                }
                Section {
                    Button(busy ? "提交中…" : "保存") {
                        guard !new1.isEmpty, new1 == new2 else { return }
                        busy = true
                        Task {
                            let ok = await HuaweiAPI.shared.changePassword(current: old, new: new1)
                            busy = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(busy || new1.isEmpty || new1 != new2)
                }
            }
            .navigationTitle("修改管理员密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
