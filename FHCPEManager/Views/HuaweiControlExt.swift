import SwiftUI

/// 华为控制页扩展：应用加速 / 双宽带 / 终端选路 / 固件升级
extension HuaweiControlView {

    // MARK: 应用加速

    internal var turboCard: some View {
        NavigationLink {
            HuaweiTurboSheet()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.yellow)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.yellow.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("应用加速").font(.system(size: 15, weight: .semibold))
                    Text("识别游戏、直播、会议，自动优化网络")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(14)
            .glassCard(radius: 18)
        }
        .buttonStyle(.plain)
    }

    // MARK: 双宽带

    internal var wanCard: some View {
        NavigationLink {
            HuaweiWanSheet()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.teal)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.teal.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("双宽带").font(.system(size: 15, weight: .semibold))
                    Text("宽带与蜂窝同时上行，可叠加带宽")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(14)
            .glassCard(radius: 18)
        }
        .buttonStyle(.plain)
    }

    // MARK: 终端选路

    internal var wanBindCard: some View {
        NavigationLink {
            HuaweiWanBindSheet()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.indigo)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.indigo.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("终端选路").font(.system(size: 15, weight: .semibold))
                    Text("指定某台终端固定走宽带或蜂窝")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(14)
            .glassCard(radius: 18)
        }
        .buttonStyle(.plain)
    }

    // MARK: 固件升级

    internal var upgradeCard: some View {
        NavigationLink {
            HuaweiUpgradeSheet()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.blue.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("固件升级").font(.system(size: 15, weight: .semibold))
                    Text("自动升级与闲时推送")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(14)
            .glassCard(radius: 18)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 应用加速

struct HuaweiTurboSheet: View {
    @EnvironmentObject var store: CpeStore
    @Environment(\.dismiss) private var dismiss

    @State private var enabled = false
    @State private var scene = 1
    @State private var selected: Set<String> = []
    @State private var hosts: [HuaweiAPI.HostItem] = []
    @State private var loading = true

    private let scenes = [(1, "游戏", "gamecontroller.fill", Color.blue),
                          (2, "直播", "dot.radiowaves.left.and.right", Color.pink),
                          (3, "会议", "video.fill", Color.green)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    toggleCard
                    if enabled {
                        sceneCard
                        deviceCard
                        saveButton
                    }
                }
                .padding(14)
            }
            .background(GlassListBackground())
            .navigationTitle("应用加速")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
            .task { await load() }
        }
    }

    private var toggleCard: some View {
        Toggle(isOn: $enabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("开启应用加速").font(.system(size: 14, weight: .medium))
                Text("智能识别游戏、直播、会议业务，自动优化网络体验")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(.green)
        .padding(14)
        .glassCard(radius: 18)
    }

    private var sceneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("加速场景").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 9) {
                ForEach(scenes, id: \.0) { s in
                    Button {
                        Haptic.selection()
                        scene = s.0
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: s.2)
                                .font(.system(size: 17))
                            Text(s.1).font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(scene == s.0 ? .white : s.3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 68)
                        .background(
                            RoundedRectangle(cornerRadius: 13)
                                .fill(scene == s.0 ? s.3 : s.3.opacity(0.10))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(sceneDesc)
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    private var sceneDesc: String {
        switch scene {
        case 1: return "智能识别游戏应用，降低延迟与抖动"
        case 2: return "智能识别直播应用，提升上传稳定性"
        default: return "智能识别会议应用，提升会议时的语音与画面稳定性"
        }
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("指定终端").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(selected.isEmpty ? "全部共享" : "\(selected.count) 台")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("不选任何终端表示全部终端共享加速。")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            ForEach(Array(hosts.enumerated()), id: \.offset) { _, h in
                Button {
                    Haptic.selection()
                    if selected.contains(h.mac) { selected.remove(h.mac) }
                    else { selected.insert(h.mac) }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: selected.contains(h.mac)
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(h.mac) ? Color.blue : Color.secondary.opacity(0.4))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(h.name).font(.system(size: 13))
                            Text(h.ip).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    private var saveButton: some View {
        Button {
            Task {
                let ok = await HuaweiAPI.shared.setTurbo(enabled: enabled,
                                                        scene: scene,
                                                        devices: Array(selected))
                store.toast(ok ? "已保存" : "保存失败", kind: ok ? .success : .error)
                if ok { dismiss() }
            }
        } label: {
            Text("保存").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.blue))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        if let t = await HuaweiAPI.shared.fetchTurbo() {
            enabled = t.enabled
            scene = t.scene
            selected = Set(t.devices)
        }
        hosts = await HuaweiAPI.shared.fetchHosts()
        loading = false
    }
}

// MARK: - 双宽带

struct HuaweiWanSheet: View {
    @EnvironmentObject var store: CpeStore
    @Environment(\.dismiss) private var dismiss

    @State private var info: HuaweiAPI.WanInfo?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    statusCard
                    tipCard
                }
                .padding(14)
            }
            .background(GlassListBackground())
            .navigationTitle("双宽带")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("网口状态").font(.system(size: 13, weight: .semibold))
                Spacer()
                if let i = info {
                    Text(i.ethernetUp ? "已连接" : "未连接")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(i.ethernetUp ? .green : .secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill((i.ethernetUp ? Color.green : Color.secondary).opacity(0.12)))
                }
            }

            if loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if let i = info {
                HStack(spacing: 0) {
                    VStack(spacing: 2) {
                        Text("协商速率").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(i.ethernetRate).font(.system(size: 15, weight: .bold))
                    }.frame(maxWidth: .infinity)
                    Divider().frame(height: 26)
                    VStack(spacing: 2) {
                        Text("宽带下行").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(String(format: "%.2f MB/s", i.wanRateRx / 1_048_576))
                            .font(.system(size: 15, weight: .bold))
                    }.frame(maxWidth: .infinity)
                    Divider().frame(height: 26)
                    VStack(spacing: 2) {
                        Text("宽带上行").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(String(format: "%.2f MB/s", i.wanRateTx / 1_048_576))
                            .font(.system(size: 15, weight: .bold))
                    }.frame(maxWidth: .infinity)
                }
                HStack {
                    Text("默认出口").font(.system(size: 12))
                    Spacer()
                    Text(i.defaultWan == "ethernet" ? "宽带" : "蜂窝")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.top, 4)

                if !i.ethernetUp {
                    Text("网口未检测到链路。插好网线后这里会显示宽带实时速率。")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
            } else {
                Text("读取不到双宽带信息，此设备可能不支持。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    private var tipCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("宽带与蜂窝同时上行可获得带宽叠加", systemImage: "info.circle")
            Label("一路断开时自动把流量并到另一路", systemImage: "arrow.triangle.swap")
            Label("具体开关请在设备网页后台设置", systemImage: "safari")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(radius: 18)
    }

    private func load() async {
        info = await HuaweiAPI.shared.fetchWan()
        loading = false
    }
}

// MARK: - 终端选路

struct HuaweiWanBindSheet: View {
    @EnvironmentObject var store: CpeStore
    @Environment(\.dismiss) private var dismiss

    @State private var hosts: [HuaweiAPI.HostItem] = []
    @State private var binding: [String: String] = [:]
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if loading {
                        ProgressView().padding(.top, 50)
                    } else if hosts.isEmpty {
                        Text("当前没有在线终端")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                            .padding(.top, 50)
                    } else {
                        ForEach(Array(hosts.enumerated()), id: \.offset) { _, h in
                            hostRow(h)
                        }
                    }
                }
                .padding(14)
            }
            .background(GlassListBackground())
            .navigationTitle("终端选路")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
            .task { await load() }
        }
    }

    private func hostRow(_ h: HuaweiAPI.HostItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(h.name).font(.system(size: 14, weight: .medium))
                    Text(h.ip).font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Picker("", selection: Binding(
                get: { binding[h.mac] ?? "" },
                set: { v in
                    binding[h.mac] = v
                    Task {
                        let ok = await HuaweiAPI.shared.setWanBind(mac: h.mac, wan: v)
                        if !ok { store.toast("设置失败", kind: .error) }
                    }
                }
            )) {
                Text("自动").tag("")
                Text("宽带").tag("ethernet")
                Text("蜂窝").tag("mobile")
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    private func load() async {
        hosts = await HuaweiAPI.shared.fetchHosts()
        binding = await HuaweiAPI.shared.fetchWanBind()
        loading = false
    }
}

// MARK: - 固件升级

struct HuaweiUpgradeSheet: View {
    @EnvironmentObject var store: CpeStore
    @Environment(\.dismiss) private var dismiss

    @State private var auto = false
    @State private var silent = false
    @State private var loading = true
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 0) {
                        Toggle(isOn: Binding(
                            get: { auto },
                            set: { auto = $0; save() }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("自动升级").font(.system(size: 14))
                                Text("发现新固件时自动下载并安装")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.green)
                        .padding(.vertical, 10)

                        Divider()

                        Toggle(isOn: Binding(
                            get: { silent },
                            set: { silent = $0; save() }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("闲时升级").font(.system(size: 14))
                                Text("允许服务器在空闲时段推送升级")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.green)
                        .padding(.vertical, 10)
                    }
                    .padding(.horizontal, 14)
                    .glassCard(radius: 18)

                    if loading {
                        ProgressView().padding(.top, 20)
                    }
                }
                .padding(14)
            }
            .background(GlassListBackground())
            .navigationTitle("固件升级")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
            .task { await load() }
        }
    }

    private func load() async {
        if let u = await HuaweiAPI.shared.fetchUpgrade() {
            auto = u.autoUpdate
            silent = u.silentUpdate
        }
        loading = false
    }

    private func save() {
        guard !busy else { return }
        busy = true
        Task {
            let ok = await HuaweiAPI.shared.setUpgrade(auto: auto, silent: silent)
            busy = false
            if !ok { store.toast("保存失败", kind: .error) }
        }
    }
}
