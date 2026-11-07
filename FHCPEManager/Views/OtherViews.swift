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
                VStack(spacing: 12) {
                    mobileDataCard
                    if store.isOppo { oppoNote }
                    else if store.isHuawei { huaweiControlCard }
                    else { carrierCard }
                    actionCard
                    rebootCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(AppBackground())
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
                        store.toast(ok ? "重启指令已发送" : "重启失败",
                                    kind: ok ? .success : .error)
                    }
                }
            } message: {
                Text("重启期间所有设备将断开网络，约需 1 分钟恢复。")
            }
        }
    }

    // MARK: 移动数据（大卡）

    private var mobileDataCard: some View {
        PanelCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11))
                    Text("移动数据")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.blue)

                Text(s["netmode"] == "3" ? "5G SA" : (s["netmode"] == "2" ? "4G" : "5G"))
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text(s.carrierName + " · " + (s.isOnline ? "已联网" : "未联网"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    bigStatTile("移动数据",
                                value: s.isOnline ? "已联网" : "未联网",
                                icon: "antenna.radiowaves.left.and.right",
                                tint: Color(red: 0.36, green: 0.55, blue: 1.0),
                                filled: true)
                    bigStatTile("VoLTE",
                                value: isOn(CpeNode.netSet + "volte_switch") ? "已开启" : "已关闭",
                                icon: "phone.circle",
                                tint: Color(red: 0.65, green: 0.5, blue: 0.98))
                }
            }
        }
    }

    /// 彩色大块状态
    private func bigStatTile(_ title: String, value: String, icon: String,
                             tint: Color, filled: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(filled ? .white : tint)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(filled ? Color.white.opacity(0.22) : tint.opacity(0.16))
                )
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(filled ? .white : .primary)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(filled ? Color.white.opacity(0.85) : Color.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(filled
                      ? AnyShapeStyle(tint.gradient)
                      : AnyShapeStyle(Color.primary.opacity(0.05)))
        )
    }

    // MARK: 网络开关

    private var carrierCard: some View {
        PanelCard(padding: 16) {
            VStack(spacing: 2) {
                PanelTitle(text: "网络开关")
                    .padding(.bottom, 8)

                SettingRow(icon: "airplane", iconTint: .orange,
                           title: "飞行模式",
                           subtitle: "关闭所有无线收发") {
                    toggleSwitch(CpeNode.netSet + "airplan_on", busyNode)
                }
                rowDivider
                SettingRow(icon: "globe.americas", iconTint: .blue,
                           title: "数据漫游",
                           subtitle: "允许漫游网络接入") {
                    toggleSwitch(CpeNode.netSet + "RoamingEnable", busyNode)
                }
                rowDivider
                SettingRow(icon: "phone.arrow.up.right", iconTint: .green,
                           title: "VoLTE",
                           subtitle: "高清语音通话") {
                    toggleSwitch(CpeNode.netSet + "volte_switch", busyNode)
                }
                rowDivider
                SettingRow(icon: "dot.radiowaves.left.and.right", iconTint: .purple,
                           title: "载波聚合",
                           subtitle: "多频段叠加提速") {
                    toggleSwitch("X_FH_MobileNetwork.NetworkInfo.CaEnable", busyNode)
                }
            }
        }
    }

    /// 华为：只提供移动数据开关
    private var huaweiControlCard: some View {
        PanelCard(padding: 16) {
            VStack(spacing: 2) {
                PanelTitle(text: "网络开关")
                    .padding(.bottom, 8)

                SettingRow(icon: "antenna.radiowaves.left.and.right", iconTint: .blue,
                           title: "移动数据",
                           subtitle: "关闭后停止蜂窝上网") {
                    Toggle("", isOn: Binding(
                        get: { !(store.status["dataOff"] == "1") },
                        set: { v in
                            Haptic.medium()
                            Task {
                                do {
                                    try await HuaweiAPI.shared.setDataSwitch(v)
                                    store.toast(v ? "移动数据已开启" : "移动数据已关闭",
                                                kind: .success)
                                    await store.fetchStatus()
                                } catch {
                                    store.toast("设置失败", kind: .error)
                                }
                            }
                        }
                    ))
                    .labelsHidden().tint(.green)
                }

                rowDivider

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("华为固件暂不支持飞行模式 / VoLTE / 载波聚合切换")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var oppoNote: some View {
        PanelCard(padding: 14) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.orange)
                Text("OPPO 设备暂不支持切换飞行模式与载波聚合")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 快捷操作

    private var actionCard: some View {
        PanelCard(padding: 16) {
            VStack(spacing: 2) {
                PanelTitle(text: "快捷操作")
                    .padding(.bottom, 8)

                Button {
                    Haptic.light()
                    showReboot = true
                } label: {
                    SettingRow(icon: "arrow.clockwise.circle", iconTint: .orange,
                               title: "重启设备",
                               subtitle: "约 1 分钟恢复") {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)

                rowDivider

                Button {
                    Haptic.light()
                    Task {
                        store.toast("正在刷新…", kind: .info)
                        await store.fetchAll()
                        store.toast("数据已更新", kind: .success)
                    }
                } label: {
                    SettingRow(icon: "arrow.triangle.2.circlepath", iconTint: .blue,
                               title: "刷新数据",
                               subtitle: "重新读取设备状态") {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rebootCard: some View {
        Button {
            Haptic.warning()
            showReboot = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "power")
                    .font(.system(size: 15, weight: .medium))
                Text("重启设备")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.95, green: 0.42, blue: 0.38))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.95, green: 0.42, blue: 0.38).opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 44)
    }

    // MARK: 逻辑

    private func isOn(_ key: String) -> Bool {
        let raw = store.status[key].lowercased()
        return raw == "1" || raw == "true" || raw == "on"
    }

    private func toggleSwitch(_ node: String, _ busy: String?) -> some View {
        let on = localOverride[node] ?? isOn(node)
        return Toggle("", isOn: Binding(
            get: { on },
            set: { newValue in
                Haptic.selection()
                pendingToggle = (node, newValue, nodeTitle(node))
            }
        ))
        .labelsHidden()
        .tint(.green)
        .disabled(busyNode == node)
    }

    private func nodeTitle(_ node: String) -> String {
        if node.contains("airplan") { return "飞行模式" }
        if node.contains("Roaming") { return "数据漫游" }
        if node.contains("volte") { return "VoLTE" }
        if node.contains("CaEnable") { return "载波聚合" }
        return "该功能"
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
                    deviceHeader
                    cellCard
                    simCard
                    wanCard
                    firmwareCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(AppBackground())
            .navigationTitle("参数")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptic.selection()
                        masked.toggle()
                    } label: {
                        Image(systemName: masked ? "eye.slash" : "eye")
                    }
                }
            }
        }
    }

    // MARK: 设备头卡

    private var deviceHeader: some View {
        PanelCard(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "wifi.router")
                        .font(.system(size: 10))
                    Text("设备 · " + (s.isOnline ? "在线" : "离线"))
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(s.isOnline ? Color.green : Color.secondary)

                Text(s.deviceModel)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text("已连接 · " + uptimeLine(s.int("uptime")))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func uptimeLine(_ t: Int) -> String {
        guard t > 0 else { return "--" }
        let d = t / 86400, h = (t % 86400) / 3600, m = (t % 3600) / 60
        if d > 0 { return "已在线 \(d) 天 \(h) 小时" }
        if h > 0 { return "已在线 \(h) 小时 \(m) 分" }
        return "已在线 \(m) 分钟"
    }

    // MARK: 蜂窝网络

    private var cellCard: some View {
        PanelCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("蜂窝网络")
                    .font(.system(size: 15, weight: .bold))
                    .padding(.bottom, 2)

                kvRow("Band", bandText)
                divider
                kvRow("PLMN", s["plmn"].isEmpty ? s.carrierName : s["plmn"])
                divider
                kvRow("PCI", s["pci"].isEmpty ? "--" : s["pci"])
                divider
                kvRow("NRARFCN", s["arfcn"].isEmpty ? "--" : s["arfcn"])
                divider
                kvRow("网络制式", s["netmode"] == "3" ? "5G SA" : "4G")
            }
        }
    }

    private var bandText: String {
        let b = s["band"].isEmpty ? "--" : "n" + s["band"]
        let w = s["bw"].isEmpty ? "" : s["bw"]
        let a = s["arfcn"].isEmpty ? "" : "@" + s["arfcn"]
        return (b + " " + w + a).trimmingCharacters(in: .whitespaces)
    }

    // MARK: SIM

    private var simCard: some View {
        PanelCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("SIM 与身份")
                    .font(.system(size: 15, weight: .bold))
                    .padding(.bottom, 2)

                kvRow("序列号", mask(s["sn"]))
                divider
                kvRow("IMEI", mask(s["imei"]))
                divider
                kvRow("IMSI", mask(s["imsi"]))
                divider
                kvRow("ICCID", mask(s["iccid"]))
                divider
                kvRow("本机号码", mask(s["phone"]))
            }
        }
    }

    private func mask(_ v: String) -> String {
        if v.isEmpty || v == "-" { return "--" }
        if !masked { return v }
        guard v.count > 6 else { return String(repeating: "•", count: v.count) }
        let head = v.prefix(3)
        let tail = v.suffix(3)
        return "\(head)\(String(repeating: "•", count: max(3, v.count - 6)))\(tail)"
    }

    // MARK: WAN

    private var wanCard: some View {
        PanelCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("WAN 与地址")
                    .font(.system(size: 15, weight: .bold))
                    .padding(.bottom, 2)

                kvRow("LAN IP", s["lanIP"].isEmpty ? "--" : s["lanIP"], copyable: true)
                divider
                kvRow("WAN IPv4", s["wanIP"].isEmpty ? "--" : s["wanIP"], copyable: true)
                divider
                kvRow("2.4G SSID", s["ssid24"].isEmpty ? "--" : s["ssid24"])
                divider
                kvRow("5G SSID", s["ssid5g"].isEmpty ? "--" : s["ssid5g"])
            }
        }
    }

    // MARK: 固件

    private var firmwareCard: some View {
        PanelCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("固件与档案")
                    .font(.system(size: 15, weight: .bold))
                    .padding(.bottom, 2)

                kvRow("软件版本", s["swver"].isEmpty ? "--" : s["swver"])
                divider
                kvRow("硬件版本", s["hwver"].isEmpty ? "--" : s["hwver"])
                divider
                kvRow("模组版本", s["modem"].isEmpty ? "--" : s["modem"])
                divider
                kvRow("厂商", s["vendor"].isEmpty ? "--" : s["vendor"])
                if let t = s.temperature {
                    divider
                    kvRow("模组温度", String(format: "%.1f °C", t))
                }
            }
        }
    }

    // MARK: 组件

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
    }

    private func kvRow(_ k: String, _ v: String, copyable: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(k)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(v)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if copyable && v != "--" {
                Button {
                    Haptic.light()
                    UIPasteboard.general.string = v
                    store.toast("已复制", kind: .success)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 3)
    }
}

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
    @State private var showSwitcher = false
    @State private var confirmLogout = false
    @AppStorage("appTheme") private var theme = "system"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    deviceCard
                    accountCard
                    appearanceCard
                    refreshCard
                    displayCard
                    diagCard
                    dangerCard
                    versionFooter
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(AppBackground())
            .navigationTitle("设置")
            .sheet(isPresented: $showConn) {
                ConnEditor().environmentObject(store)
            }
            .sheet(isPresented: $showSwitcher) {
                DeviceSwitcher().environmentObject(store)
            }
            .alert("退出登录", isPresented: $confirmLogout) {
                Button("取消", role: .cancel) { }
                Button("退出", role: .destructive) {
                    Haptic.warning()
                    store.isLoggedIn = false
                    store.stopPolling()
                    store.toast("已退出登录", kind: .info)
                }
            } message: {
                Text("密码会保留在本机，下次可自动登录。")
            }
        }
    }

    // MARK: 设备

    private var deviceCard: some View {
        PanelCard(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "wifi.router")
                        .font(.system(size: 10))
                    Text("后台连接")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(.blue)

                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.activeProfile?.displayTitle ?? "未连接")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text(Settings.load().host + " · " + Settings.load().user)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(store.isLoggedIn ? Color.green : Color.red)
                        .frame(width: 9, height: 9)
                }
                .padding(.top, 2)

                HStack(spacing: 10) {
                    smallBtn("连接设置", "antenna.radiowaves.left.and.right") {
                        showConn = true
                    }
                    smallBtn("切换设备", "arrow.left.arrow.right") {
                        showSwitcher = true
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func smallBtn(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.light()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(.blue)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.blue.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 账号

    private var accountCard: some View {
        PanelCard(padding: 16) {
            VStack(spacing: 2) {
                PanelTitle(text: "账号与安全")
                    .padding(.bottom, 8)

                SettingRow(icon: "key", iconTint: .blue,
                           title: "保存密码",
                           subtitle: "密码存在系统钥匙串") {
                    Toggle("", isOn: Binding(
                        get: { UserDefaults.standard.object(forKey: "rememberPass") as? Bool ?? true },
                        set: { v in
                            UserDefaults.standard.set(v, forKey: "rememberPass")
                            Haptic.medium()
                        }
                    ))
                    .labelsHidden().tint(.green)
                }
                rowDivider
                SettingRow(icon: "bolt.badge.clock", iconTint: .green,
                           title: "自动登录",
                           subtitle: "打开 App 时自动连接设备") {
                    Toggle("", isOn: Binding(
                        get: { UserDefaults.standard.object(forKey: "autoLogin") as? Bool ?? true },
                        set: { v in
                            UserDefaults.standard.set(v, forKey: "autoLogin")
                            Haptic.medium()
                        }
                    ))
                    .labelsHidden().tint(.green)
                }
                rowDivider

                Button {
                    Haptic.warning()
                    confirmLogout = true
                } label: {
                    SettingRow(icon: "rectangle.portrait.and.arrow.right",
                               iconTint: Color(red: 0.95, green: 0.42, blue: 0.38),
                               title: "退出登录",
                               subtitle: "保留本机密码") {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 外观

    private var appearanceCard: some View {
        PanelCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("外观")
                    .font(.system(size: 15, weight: .bold))
                Text("跟随系统或固定深浅色")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    themeItem("浅色", "light")
                    themeItem("深色", "dark")
                    themeItem("跟随系统", "system")
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .padding(.top, 2)
            }
        }
    }

    private func themeItem(_ title: String, _ value: String) -> some View {
        Button {
            Haptic.selection()
            theme = value
            applyAppearance(value)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: theme == value ? .semibold : .regular))
                .foregroundStyle(theme == value ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme == value ? Color.blue.opacity(0.18) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme == value ? Color.blue.opacity(0.5) : Color.clear,
                                      lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: 刷新

    private var refreshCard: some View {
        PanelCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("数据刷新")
                    .font(.system(size: 15, weight: .bold))

                HStack(spacing: 0) {
                    ForEach([0.5, 1.0, 1.5, 2.0, 3.0, 5.0], id: \.self) { v in
                        Button {
                            Haptic.selection()
                            store.refreshInterval = v
                            store.startPolling()
                        } label: {
                            Text(v == 0.5 ? "0.5s" : "\(Int(v))s")
                                .font(.system(size: 12.5,
                                              weight: store.refreshInterval == v ? .semibold : .regular))
                                .foregroundStyle(store.refreshInterval == v
                                                 ? Color.primary : Color.secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(store.refreshInterval == v
                                              ? Color.primary.opacity(0.08) : Color.clear)
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
        }
    }

    // MARK: 显示

    private var displayCard: some View {
        PanelCard(padding: 16) {
            VStack(spacing: 2) {
                PanelTitle(text: "显示与诊断")
                    .padding(.bottom, 8)

                SettingRow(icon: "sun.max", iconTint: .orange,
                           title: "屏幕常亮",
                           subtitle: "分屏挂机时保持刷新") {
                    Toggle("", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "keepAwake") },
                        set: { v in
                            UserDefaults.standard.set(v, forKey: "keepAwake")
                            UIApplication.shared.isIdleTimerDisabled = v
                            Haptic.medium()
                        }
                    ))
                    .labelsHidden().tint(.green)
                }
            }
        }
    }

    private var diagCard: some View {
        PanelCard(padding: 16) {
            NavigationLink {
                DiagView().environmentObject(store)
            } label: {
                SettingRow(icon: "stethoscope", iconTint: .purple,
                           title: "连接诊断",
                           subtitle: "检测登录与数据读取") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 危险操作

    private var dangerCard: some View {
        PanelCard(padding: 16) {
            VStack(spacing: 2) {
                PanelTitle(text: "设备维护")
                    .padding(.bottom, 8)

                Button {
                    Haptic.warning()
                    Task {
                        let ok = await store.reboot()
                        store.toast(ok ? "重启指令已发送" : "重启失败",
                                    kind: ok ? .success : .error)
                    }
                } label: {
                    SettingRow(icon: "arrow.clockwise.circle", iconTint: .orange,
                               title: "重启设备",
                               subtitle: "约 1 分钟恢复") {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var versionFooter: some View {
        VStack(spacing: 4) {
            Text("CPE 管理 v" + appVersion)
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.7))
            Text(store.isOppo ? "OPPO CPE" : "烽火 CPE")
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .padding(.top, 6)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 44)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
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

