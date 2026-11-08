import SwiftUI

/// 华为控制页 —— 照 CPE Ultra 布局
struct HuaweiControlView: View {
    @EnvironmentObject var store: CpeStore

    @State private var dataOn = true
    @State private var ipv6On = false
    @State private var turboOn = false
    @State private var failoverOn = false
    @State private var turboEngine = false
    @State private var ledOn = true
    @State private var ambientOn = false
    @State private var busy = false
    @State private var partialWarn = false
    @State private var dualWan: [String: Any] = [:]
    @State private var hostCount = 0

    private var s: CpeStatus { store.status }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    mobileDataCard

                    if partialWarn {
                        warnBar
                    }

                    turboEngineCard
                    dualWanCard
                    ambientCard
                    vpnCard
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 96)
            }
            .background(GlassListBackground())
            .navigationBarHidden(true)
            .refreshable { await reload() }
            .task { await reload() }
        }
    }

    // MARK: 移动数据大卡

    private var mobileDataCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 5) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 11))
                Text("移动数据")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.blue)

            Text(netModeText)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(s.carrierName + " · " + (s["regstatus"] == "0" ? "蜂窝上行正常" : "未联网"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                bigTile("移动数据", dataOn ? "已联网" : "已关闭",
                        icon: "antenna.radiowaves.left.and.right",
                        tint: Color(red: 0.38, green: 0.62, blue: 1.0),
                        filled: dataOn) {
                    Task { await toggleData() }
                }
                bigTile("IPv6", ipv6On ? "双栈" : "已关闭",
                        icon: "6.circle.fill",
                        tint: Color(red: 0.68, green: 0.55, blue: 1.0),
                        filled: ipv6On) {
                    Task { await toggleIPv6() }
                }
            }
        }
        .padding(16)
        .glassCard(radius: 22)
    }

    private func bigTile(_ title: String, _ value: String, icon: String,
                         tint: Color, filled: Bool,
                         action: @escaping () -> Void) -> some View {
        Button {
            Haptic.light()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(filled ? Color.white.opacity(0.22) : tint.opacity(0.16))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(filled ? .white : tint)
                }
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(filled ? .white : .primary)
                Text(value)
                    .font(.system(size: 11.5))
                    .foregroundStyle(filled ? Color.white.opacity(0.85) : Color.secondary)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(filled
                          ? AnyShapeStyle(tint.gradient)
                          : AnyShapeStyle(Color.primary.opacity(0.05)))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 警告条

    private var warnBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.orange.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("部分状态没能读回来")
                    .font(.system(size: 13, weight: .semibold))
                Text("游戏加速、氛围灯没能读回来。下拉刷新可重试。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .glassCard(radius: 18)
    }

    // MARK: 应用加速

    private var turboEngineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("应用加速")
                .font(.system(size: 15, weight: .bold))

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("加速引擎")
                        .font(.system(size: 13.5, weight: .medium))
                    Text("关闭后所有终端平等排队")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { turboEngine },
                    set: { v in
                        turboEngine = v
                        Haptic.medium()
                        Task {
                            let ok = await HuaweiAPI.shared.setTurbo(enabled: v, scene: 0, devices: [])
                            store.toast(ok ? "已" + (v ? "开启" : "关闭") : "设置失败",
                                        kind: ok ? .success : .error)
                        }
                    }
                ))
                .labelsHidden()
                .tint(.green)
            }
        }
        .padding(16)
        .glassCard(radius: 22)
    }

    // MARK: 双宽带 Turbo

    private var dualWanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("双宽带 Turbo")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text("网线已连接")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.14)))
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("双通道聚合")
                        .font(.system(size: 13.5, weight: .medium))
                    Text("宽带与 SIM 卡同时上行，带宽叠加")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $turboOn)
                    .labelsHidden().tint(.green)
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("断线自动切换")
                        .font(.system(size: 13.5, weight: .medium))
                    Text("一路断开时自动把流量并到另一路")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $failoverOn)
                    .labelsHidden().tint(.blue)
            }

            HStack(spacing: 10) {
                wanBox("宽带下行", "0", .blue)
                wanBox("宽带上行", "0", .orange)
            }

            Button {
                Haptic.light()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "cable.connector")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                    Text("宽带链路")
                        .font(.system(size: 13))
                    Spacer()
                    Text(ethRate)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .glassCard(radius: 22)
    }

    private var ethRate: String {
        if let r = dualWan["ethwanrate"] as? String, !r.isEmpty { return r }
        return "1000 Mbps"
    }

    private func wanBox(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text("Mbps")
                    .font(.system(size: 9))
                    .foregroundStyle(color.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: 氛围灯

    private var ambientCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("氛围灯")
                .font(.system(size: 15, weight: .bold))

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("指示灯")
                        .font(.system(size: 13.5, weight: .medium))
                    Text(ledOn ? "正常显示" : "全部熄灭")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { ledOn },
                    set: { v in
                        ledOn = v
                        Haptic.medium()
                        Task {
                            _ = await HuaweiAPI.shared.setLed(v)
                        }
                    }
                ))
                .labelsHidden().tint(.green)
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("定时熄灯")
                        .font(.system(size: 13.5, weight: .medium))
                    Text(ambientOn ? "已设置时间段" : "全天保持当前状态")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $ambientOn)
                    .labelsHidden().tint(.green)
            }
        }
        .padding(16)
        .glassCard(radius: 22)
    }

    // MARK: VPN

    private var vpnCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VPN 拨号")
                .font(.system(size: 15, weight: .bold))

            vpnRow("PPTP", "未启用", "未填写服务器地址")
            Divider().opacity(0.2)
            vpnRow("L2TP", "未启用", "未填写 LNS 地址")
            Divider().opacity(0.2)

            HStack {
                Image(systemName: "shield.checkerboard")
                    .font(.system(size: 12))
                    .foregroundStyle(.purple)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.purple.opacity(0.12)))
                Text("IPSec")
                    .font(.system(size: 13))
                Spacer()
                Text("只读")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glassCard(radius: 22)
    }

    private func vpnRow(_ name: String, _ state: String, _ detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(name)
                        .font(.system(size: 13.5, weight: .semibold))
                    Circle().fill(Color.gray.opacity(0.4)).frame(width: 5, height: 5)
                    Text(state)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Haptic.light()
                store.toast("VPN 配置请到设备后台设置", kind: .info)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "square.and.pencil").font(.system(size: 10))
                    Text("填写").font(.system(size: 11))
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.blue.opacity(0.10)))
            }
            .buttonStyle(.plain)

            Toggle("", isOn: .constant(false))
                .labelsHidden().tint(.green)
                .disabled(true)
                .scaleEffect(0.85)
        }
    }

    // MARK: 逻辑

    private var netModeText: String {
        s["netmode"] == "3" ? "5G SA" : (s["netmode"] == "2" ? "4G" : "5G")
    }

    private func reload() async {
        // 移动数据
        let ds = await HuaweiBridge.shared.get("homeDataSwitch")
        if let v = ds["dataswitch"] as? String {
            dataOn = (v == "1")
        }
        // IPv6
        let v6 = await HuaweiBridge.shared.get("ipv6Enable")
        if let v = v6["ipv6_enable"] as? String {
            ipv6On = (v == "1")
        }
        // 双 WAN
        let dw = await HuaweiBridge.shared.get("dualWanInfo")
        dualWan = dw
        if let m = dw["dualwanmode"] as? String {
            turboOn = (m != "0")
        }
    }

    private func toggleData() async {
        let next = !dataOn
        let ok = await HuaweiAPI.shared.setMobileData(next)
        if ok {
            dataOn = next
            store.toast(next ? "移动数据已开启" : "移动数据已关闭", kind: .success)
        } else {
            store.toast("设置失败", kind: .error)
        }
    }

    private func toggleIPv6() async {
        let next = !ipv6On
        let r = await HuaweiBridge.shared.post("ipv6Enable", ["ipv6_enable": next ? 1 : 0])
        if r["__err"] == nil {
            ipv6On = next
            store.toast(next ? "IPv6 已开启" : "IPv6 已关闭", kind: .success)
        } else {
            store.toast("设置失败", kind: .error)
        }
    }
}
