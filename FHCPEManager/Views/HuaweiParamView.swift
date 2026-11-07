import SwiftUI

/// 华为参数页：设备信息 / 网络 / SIM / WLAN 高级 / 天线 / VPN / MAC 过滤
struct HuaweiParamView: View {
    @EnvironmentObject var store: CpeStore

    @State private var masked = true
    @State private var revealed: Set<String> = []
    @State private var showAntenna = false
    @State private var showWlan = false
    @State private var showMac = false
    @State private var showVpn = false

    private var s: CpeStatus { store.status }

    var body: some View {
        NavigationStack {
            WideAdapter(maxWidth: 560) {
                ScrollView {
                    VStack(spacing: 12) {
                        overviewCard
                        infoCard("设备信息", icon: "cpu", rows: [
                            ("设备型号", s["model"], false),
                            ("序列号", s["sn"], true),
                            ("IMEI", s["imei"], true),
                            ("IMSI", s["imsi"], true),
                            ("ICCID", s["iccid"], true),
                            ("硬件版本", s["hwver"], false),
                            ("软件版本", s["swver"], false),
                            ("MAC 地址", s["mac"], false)
                        ])
                        infoCard("网络", icon: "wifi", rows: [
                            ("运营商", s.carrierName, false),
                            ("PLMN", s["plmn"], false),
                            ("网络制式", netModeText, false),
                            ("注册状态", s["regstatus"] == "0" ? "已注册" : "未注册", false),
                            ("漫游状态", s["roaming"] == "1" ? "漫游中" : "非漫游", false)
                        ])
                        entryCard
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                    .frame(maxWidth: .infinity)
                }
                .navigationTitle("参数")
            }
            .background(GlassListBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptic.light()
                        masked.toggle()
                        if !masked { revealed.removeAll() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: masked ? "eye.slash" : "eye")
                                .font(.system(size: 12))
                            Text(masked ? "一键显示" : "全部隐藏")
                                .font(.system(size: 12))
                        }
                    }
                }
            }
            .sheet(isPresented: $showAntenna) { HuaweiAntennaSheet().environmentObject(store) }
            .sheet(isPresented: $showWlan) { HuaweiWlanSheet().environmentObject(store) }
            .sheet(isPresented: $showMac) { HuaweiMacFilterSheet().environmentObject(store) }
            .sheet(isPresented: $showVpn) { HuaweiVpnSheet().environmentObject(store) }
        }
    }

    private var netModeText: String {
        switch s["netmode"] {
        case "3": return "5G"
        case "2": return "4G"
        default:  return s["netmode"].isEmpty ? "--" : s["netmode"]
        }
    }

    private var overviewCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("设备型号").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(s.deviceModel)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            Spacer()
            if let b = Int(s["battery"]), b > 0 {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("电量").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(b)%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(b > 20 ? Color.green : Color.red)
                }
            }
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    private var entryCard: some View {
        VStack(spacing: 0) {
            entry("天线设置", "antenna.radiowaves.left.and.right", .blue) { showAntenna = true }
            Divider().padding(.leading, 46)
            entry("WLAN 高级设置", "wifi", .teal) { showWlan = true }
            Divider().padding(.leading, 46)
            entry("MAC 地址过滤", "shield.lefthalf.filled", .orange) { showMac = true }
            Divider().padding(.leading, 46)
            entry("VPN 配置", "lock.shield", .purple) { showVpn = true }
        }
        .padding(.vertical, 4)
        .glassCard(radius: 18)
    }

    private func entry(_ title: String, _ icon: String, _ tint: Color,
                       action: @escaping () -> Void) -> some View {
        Button {
            Haptic.light()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(tint.opacity(0.12)))
                Text(title).font(.system(size: 14.5)).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func infoCard(_ title: String, icon: String,
                          rows: [(String, String, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)],
                      alignment: .leading, spacing: 9) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.0).font(.system(size: 10)).foregroundStyle(.secondary)

                        if r.2 && masked && !revealed.contains(r.0) {
                            Button {
                                Haptic.light()
                                _ = revealed.insert(r.0)
                            } label: {
                                HStack(spacing: 3) {
                                    Text("••••••••")
                                        .font(.system(size: 12.5, weight: .medium))
                                    Text("显示").font(.system(size: 9))
                                        .foregroundStyle(.blue.opacity(0.8))
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(r.1.isEmpty || r.1 == "-" ? "--" : r.1)
                                .font(.system(size: 12.5, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .glassCard(radius: 18)
    }
}

// MARK: - 天线设置

struct HuaweiAntennaSheet: View {
    @EnvironmentObject var store: CpeStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: HuaweiAPI.AntennaMode = .auto
    @State private var ant1 = "-"
    @State private var ant2 = "-"
    @State private var supported = true
    @State private var loading = true
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if !supported {
                        unsupported
                    } else {
                        statusCard
                        modePicker
                        saveButton
                    }
                }
                .padding(14)
            }
            .background(GlassListBackground())
            .navigationTitle("天线设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private var unsupported: some View {
        VStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("这台设备没有开放天线设置")
                .font(.system(size: 15, weight: .semibold))
            Text("这台设备的固件没开放天线设置，网页后台里那一块同样不会显示。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .padding(.top, 50)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("天线状态").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("天线 1").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(ant1).font(.system(size: 15, weight: .bold))
                }.frame(maxWidth: .infinity)
                Divider().frame(height: 26)
                VStack(spacing: 2) {
                    Text("天线 2").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(ant2).font(.system(size: 15, weight: .bold))
                }.frame(maxWidth: .infinity)
            }
            Text("这两行由设备实测，随所选档位变化。")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("天线档位").font(.system(size: 13, weight: .semibold))
            ForEach(HuaweiAPI.AntennaMode.allCases, id: \.rawValue) { m in
                Button {
                    Haptic.selection()
                    mode = m
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: mode == m ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(mode == m ? Color.blue : Color.secondary.opacity(0.4))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title).font(.system(size: 14, weight: .medium))
                            Text(m.detail).font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
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
            save()
        } label: {
            HStack(spacing: 6) {
                if busy { ProgressView().tint(.white).scaleEffect(0.8) }
                Text(busy ? "保存中…" : "保存天线设置")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.blue))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func load() async {
        loading = true
        if let a = await HuaweiAPI.shared.fetchAntenna() {
            mode = HuaweiAPI.AntennaMode(rawValue: a.mode) ?? .auto
            ant1 = a.ant1
            ant2 = a.ant2
            supported = true
        } else {
            supported = false
        }
        loading = false
    }

    private func save() {
        busy = true
        Task {
            let ok = await HuaweiAPI.shared.setAntenna(mode)
            busy = false
            store.toast(ok ? "天线设置已保存" : (HuaweiAPI.shared.lastErrorText.isEmpty
                                            ? "保存失败" : HuaweiAPI.shared.lastErrorText),
                        kind: ok ? .success : .error)
            if ok { await load() }
        }
    }
}

// MARK: - WLAN 高级

struct HuaweiWlanSheet: View {
    @EnvironmentObject var store: CpeStore
    @Environment(\.dismiss) private var dismiss

    @State private var bands: [HuaweiAPI.WlanBand] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if loading {
                        ProgressView().padding(.top, 50)
                    } else if bands.isEmpty {
                        Text("读取不到无线配置")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                            .padding(.top, 50)
                    } else {
                        ForEach(bands.indices, id: \.self) { i in
                            bandCard(i)
                        }
                    }
                }
                .padding(14)
            }
            .background(GlassListBackground())
            .navigationTitle("WLAN 高级设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func bandCard(_ i: Int) -> some View {
        let b = bands[i]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(b.index == 1 ? "2.4 GHz" : "5 GHz")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { bands[i].ssidEnable },
                    set: { bands[i].ssidEnable = $0; save(i) }
                )).labelsHidden()
            }

            HStack {
                Text("网络名称").font(.system(size: 12))
                Spacer()
                TextField("SSID", text: Binding(
                    get: { bands[i].ssid },
                    set: { bands[i].ssid = $0 }
                ))
                .multilineTextAlignment(.trailing)
                .font(.system(size: 13))
            }

            HStack {
                Text("信道").font(.system(size: 12))
                Spacer()
                TextField("0", text: Binding(
                    get: { bands[i].channel },
                    set: { bands[i].channel = $0 }
                ))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                Text("（0 = 自动）").font(.system(size: 10)).foregroundStyle(.secondary)
            }

            HStack {
                Text("发射功率").font(.system(size: 12))
                Spacer()
                Picker("", selection: Binding(
                    get: { bands[i].power },
                    set: { bands[i].power = $0; save(i) }
                )) {
                    Text("省电").tag("0")
                    Text("标准").tag("1")
                    Text("穿墙").tag("2")
                }
                .pickerStyle(.menu)
            }

            Button {
                save(i)
            } label: {
                Text("保存这一频段")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    private func load() async {
        bands = await HuaweiAPI.shared.fetchWlan()
        loading = false
    }

    private func save(_ i: Int) {
        Task {
            let ok = await HuaweiAPI.shared.setWlan(bands[i])
            store.toast(ok ? "已保存" : "保存失败", kind: ok ? .success : .error)
        }
    }
}

// MARK: - MAC 过滤

struct HuaweiMacFilterSheet: View {
    @EnvironmentObject var store: CpeStore
    @Environment(\.dismiss) private var dismiss

    @State private var enabled = false
    @State private var policy = 0
    @State private var macs: [String] = []
    @State private var newMac = ""
    @State private var loading = true
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if loading {
                        ProgressView().padding(.top, 50)
                    } else {
                        settingCard
                        listCard
                    }
                }
                .padding(14)
            }
            .background(GlassListBackground())
            .navigationTitle("MAC 地址过滤")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private var settingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("启用 MAC 过滤", isOn: Binding(
                get: { enabled },
                set: { enabled = $0; save() }
            ))
            .font(.system(size: 13, weight: .semibold))

            Picker("", selection: Binding(
                get: { policy },
                set: { policy = $0; save() }
            )) {
                Text("黑名单").tag(0)
                Text("白名单").tag(1)
            }
            .pickerStyle(.segmented)

            Text(policy == 1
                 ? "白名单模式：只有名单里的设备能上网。改名单会立刻影响已连接设备。"
                 : "黑名单模式：名单里的设备无法上网。")
                .font(.system(size: 11))
                .foregroundStyle(policy == 1 ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("名单").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(macs.count) 条").font(.system(size: 11)).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("AA:BB:CC:DD:EE:FF", text: $newMac)
                    .font(.system(size: 12, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.05)))
                Button("添加") {
                    let m = newMac.trimmingCharacters(in: .whitespaces).uppercased()
                    guard m.contains(":") else { return }
                    macs.append(m)
                    newMac = ""
                    save()
                }
                .font(.system(size: 13, weight: .medium))
                .disabled(newMac.isEmpty)
            }

            ForEach(Array(macs.enumerated()), id: \.offset) { idx, m in
                HStack {
                    Text(m).font(.system(size: 12, design: .monospaced))
                    Spacer()
                    Button {
                        macs.remove(at: idx)
                        save()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red.opacity(0.8))
                    }
                }
                .padding(.vertical, 3)
            }

            if macs.isEmpty {
                Text("名单为空").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    private func load() async {
        if let st = await HuaweiAPI.shared.fetchMacFilter() {
            enabled = st.enabled
            policy = st.policy
            macs = st.hosts.map { $0.mac }
        }
        loading = false
    }

    private func save() {
        guard !busy else { return }
        busy = true
        Task {
            let ok = await HuaweiAPI.shared.setMacFilter(enabled: enabled, policy: policy, macs: macs)
            busy = false
            if !ok {
                store.toast("保存失败", kind: .error)
            }
        }
    }
}

// MARK: - VPN

struct HuaweiVpnSheet: View {
    @EnvironmentObject var store: CpeStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind = "ipsec"
    @State private var list: [HuaweiAPI.VpnProfile] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Picker("", selection: $kind) {
                        Text("IPSec").tag("ipsec")
                        Text("L2TP").tag("l2tp")
                        Text("PPTP").tag("pptp")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _ in Task { await load() } }

                    if loading {
                        ProgressView().padding(.top, 40)
                    } else if list.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(.secondary.opacity(0.4))
                            Text("没有已配置的隧道")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                            Text("IPSec 参数较多，建议在设备网页后台配置。")
                                .font(.system(size: 11)).foregroundStyle(.secondary.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)
                    } else {
                        ForEach(Array(list.enumerated()), id: \.offset) { _, v in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(v.name).font(.system(size: 14, weight: .semibold))
                                HStack {
                                    Text(v.server).font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(v.user).font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(radius: 16)
                        }
                    }
                }
                .padding(14)
            }
            .background(GlassListBackground())
            .navigationTitle("VPN 配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        loading = true
        list = await HuaweiAPI.shared.fetchVpn(kind)
        loading = false
    }
}
