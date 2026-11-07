import SwiftUI

// MARK: - 锁频

struct LockBandView: View {
    @EnvironmentObject var store: CpeStore

    @State private var tab = 0                      // 0 网络首选 / 1 锁频 / 2 天线
    @State private var lockEnabled = false
    @State private var selectedNR: Set<Int> = []
    @State private var selectedLTE: Set<Int> = []
    @State private var carrierEnabled = false
    @State private var carrierSerial = ""
    @State private var busy = false
    @State private var showConfirm = false
    @State private var pendingAction = ""

    private let nrBands = [1, 3, 5, 8, 28, 41, 77, 78, 79]
    private let lteBands = [1, 3, 5, 8, 34, 38, 39, 40, 41]

    private var s: CpeStatus { store.status }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    currentLockBanner
                    tabBar
                    switch tab {
                    case 0: networkModeCard
                    case 1: lockCard
                    default: antennaCard
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(AppBackground())
            .navigationTitle("锁频")
            .task { loadCurrent() }
            .alert("确认应用", isPresented: $showConfirm) {
                Button("取消", role: .cancel) { }
                Button("应用") {
                    Haptic.medium()
                    applyPending()
                }
            } message: {
                Text(pendingAction == "band"
                     ? "将锁定所选频段，设备会重新注册网络，短暂断网约 30 秒。"
                     : "将锁定运营商，设备会重新注册网络。")
            }
        }
    }

    // MARK: 顶部当前锁定状态

    private var currentLockBanner: some View {
        PanelCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: s["lockbandEn"] == "1"
                          ? "lock.fill" : "lock.open")
                        .font(.system(size: 10))
                    Text(s["lockbandEn"] == "1" ? "当前锁定" : "当前未锁定")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(s["lockbandEn"] == "1" ? Color.green : Color.secondary)

                Text(currentLockText)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(s["lockbandEn"] == "1" ? Color.green : Color.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Text(lockSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var currentLockText: String {
        if s["lockbandEn"] != "1" { return "未锁定频段" }
        var parts: [String] = []
        let band = s["band"].isEmpty ? "--" : "n" + s["band"]
        let arfcn = s["arfcn"].isEmpty ? "" : " " + s["arfcn"]
        let pci = s["pci"].isEmpty ? "" : " · PCI " + s["pci"]
        parts.append(band + arfcn + pci)
        return parts.joined()
    }

    private var lockSummary: String {
        let nr = s["lockbandNr"].isEmpty ? "5G 不锁定" : "5G 已选 \(s["lockbandNr"])"
        let lte = s["lockbandLte"].isEmpty ? "4G 不锁定" : "4G 已选 \(s["lockbandLte"])"
        return nr + " · " + lte
    }

    // MARK: Tab

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabItem("网络首选", 0)
            tabItem("锁频", 1)
            tabItem("天线设置", 2)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func tabItem(_ title: String, _ idx: Int) -> some View {
        Button {
            Haptic.selection()
            withAnimation(.easeInOut(duration: 0.2)) { tab = idx }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: tab == idx ? .semibold : .regular))
                .foregroundStyle(tab == idx ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tab == idx ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: 网络首选

    private var networkModeCard: some View {
        PanelCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 10))
                        Text("网络首选方式")
                            .font(.system(size: 11.5))
                    }
                    .foregroundStyle(.blue)

                    Text(s["netmode"] == "3" ? "5G 优先" : "4G 优先")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)

                    Text("修改后设备会重新注册网络，短暂断网")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    modeTile("飞行模式", isOn(CpeNode.netSet + "airplan_on"))
                    modeTile("数据漫游", isOn(CpeNode.netSet + "RoamingEnable"))
                    modeTile("载波聚合", isOn("X_FH_MobileNetwork.NetworkInfo.CaEnable"))
                }
            }
        }
    }

    private func modeTile(_ title: String, _ on: Bool) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Text(on ? "已开启" : "已关闭")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(on ? Color.green : Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: 锁频

    private var lockCard: some View {
        VStack(spacing: 12) {
            // 5G
            PanelCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("5G NR 频段")
                            .font(.system(size: 15, weight: .bold))
                        Spacer()
                        Toggle("", isOn: $lockEnabled)
                            .labelsHidden()
                            .tint(.green)
                    }

                    Text("已选 \(selectedNR.count) 个")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 8) {
                        ForEach(nrBands, id: \.self) { b in
                            bandChip("n\(b)", selectedNR.contains(b)) {
                                toggleBand(b, &selectedNR)
                            }
                        }
                    }
                }
            }

            // 4G
            PanelCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("4G LTE 频段")
                        .font(.system(size: 15, weight: .bold))

                    FlowLayout(spacing: 8) {
                        ForEach(lteBands, id: \.self) { b in
                            bandChip("B\(b)", selectedLTE.contains(b)) {
                                toggleBand(b, &selectedLTE)
                            }
                        }
                    }
                }
            }

            // 运营商锁定
            PanelCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("运营商锁定")
                            .font(.system(size: 15, weight: .bold))
                        Spacer()
                        Toggle("", isOn: $carrierEnabled)
                            .labelsHidden()
                            .tint(.green)
                    }

                    TextField("运营商代码（可选）", text: $carrierSerial)
                        .font(.system(size: 14))
                        .padding(11)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                }
            }

            // 应用按钮
            Button {
                Haptic.medium()
                pendingAction = "band"
                showConfirm = true
            } label: {
                HStack(spacing: 6) {
                    if busy { ProgressView().tint(.white).scaleEffect(0.8) }
                    Text(busy ? "应用中…" : "应用锁频设置")
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.blue)
                )
            }
            .disabled(busy)
        }
    }

    private func bandChip(_ label: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.selection()
            action()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Color.white : Color.primary.opacity(0.8))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(on ? Color.blue : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleBand(_ b: Int, _ set: inout Set<Int>) {
        if set.contains(b) { set.remove(b) } else { set.insert(b) }
    }

    // MARK: 天线

    private var antennaCard: some View {
        PanelCard(padding: 16) {
            VStack(spacing: 14) {
                HStack(spacing: 5) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 11))
                    Text("天线设置 · 不可用")
                        .font(.system(size: 11.5))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("不支持")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("这台设备的固件没有开放天线设置接口，网页后台中同样不会显示。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Image(systemName: "wifi.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary.opacity(0.25))
                    .padding(.vertical, 20)
            }
        }
    }

    // MARK: 逻辑

    private func isOn(_ key: String) -> Bool {
        let raw = store.status[key].lowercased()
        return raw == "1" || raw == "true" || raw == "on"
    }

    private func loadCurrent() {
        lockEnabled = s["lockbandEn"] == "1"
        carrierEnabled = s["carrierLockEn"] == "1"
        carrierSerial = s["carrierLockNum"]
        selectedNR = Set(s["lockbandNr"].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
        selectedLTE = Set(s["lockbandLte"].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    private func applyPending() {
        busy = true
        Task {
            defer { busy = false }
            let ok = await store.applyBandLock(
                enable: lockEnabled,
                nr: Array(selectedNR).sorted(),
                lte: Array(selectedLTE).sorted())
            store.toast(ok ? "频段锁定已应用" : "应用失败，请检查连接",
                        kind: ok ? .success : .error)
        }
    }
}

// MARK: - 流式布局（频段胶囊换行）

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x + sz.width > maxW && x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
