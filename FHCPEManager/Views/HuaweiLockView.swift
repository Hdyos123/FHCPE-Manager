import SwiftUI

/// 华为锁频页：频段 / 频点 / 锁小区 / 解除
struct HuaweiLockView: View {
    @EnvironmentObject var store: CpeStore

    @State private var mode = 0                 // 0 频段 1 频点 2 锁小区 3 解除
    @State private var current: [String: String] = [:]
    @State private var neighbors: [HuaweiAPI.CellEntry] = []
    @State private var serving: HuaweiAPI.CellEntry? = nil
    @State private var loading = false
    @State private var busy = false

    @State private var bandText = ""
    @State private var freqText = ""
    @State private var cellBand = ""
    @State private var cellFreq = ""
    @State private var cellPci = ""
    @State private var showConfirm = false

    private let modes = ["频段", "频点", "锁小区", "解除"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    currentCard
                    modePicker
                    editorCard
                    neighborCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .scrollContentBackground(.hidden)
            .background(GlassListBackground())
            .navigationTitle("锁频")
            .refreshable { await reload() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await reload() }
                    } label: {
                        if loading { ProgressView().scaleEffect(0.8) }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(loading)
                }
            }
            .alert("写入锁频配置", isPresented: $showConfirm) {
                Button("取消", role: .cancel) { }
                Button("写入", role: .destructive) {
                    Task { await apply() }
                }
            } message: {
                Text("锁频后设备会重新搜网，期间断线十几秒。\n如果锁定的频点当前不可用，会一直没有信号。")
            }
            .task { await reload() }
        }
    }

    // MARK: 当前锁定

    private var currentCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("当前锁定")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if current.isEmpty {
                Text("没有读取到锁定配置")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(current.keys.sorted()), id: \.self) { k in
                        HStack {
                            Text(labelFor(k))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(current[k]?.isEmpty == false ? current[k]! : "未锁定")
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    private var summary: String {
        if current.isEmpty { return "—" }
        let locked = current.values.contains { !$0.isEmpty && $0 != "0" }
        return locked ? "已锁定" : "自动"
    }

    private func labelFor(_ k: String) -> String {
        switch k {
        case "lteBand": return "4G 频段"
        case "lteFreq": return "4G 频点"
        case "nrBand":  return "5G 频段"
        case "nrFreq":  return "5G 频点"
        case "nrCell":  return "5G 小区"
        default:        return k
        }
    }

    // MARK: 模式

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(0..<modes.count, id: \.self) { i in
                Text(modes[i]).tag(i)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: 编辑区

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch mode {
            case 0:
                field("5G 频段", $bandText, "例如 78 或 41")
                hint("只允许使用勾选的频段，频点仍由基站决定。多个用逗号分隔。")
            case 1:
                field("5G 频点 (NRARFCN)", $freqText, "例如 627264")
                hint("固定在指定频点，不限定具体小区。")
            case 2:
                field("频段", $cellBand, "例如 78")
                field("频点", $cellFreq, "例如 627264")
                field("PCI", $cellPci, "例如 96")
                hint("固定到某个基站的某个小区，最精确也最容易失联。")
            default:
                hint("会清空全部锁定配置，设备重新自动搜网，期间断线十几秒。")
            }

            Button {
                Haptic.warning()
                showConfirm = true
            } label: {
                HStack(spacing: 6) {
                    if busy { ProgressView().tint(.white).scaleEffect(0.8) }
                    Text(mode == 3 ? "解除全部锁定" : "写入锁频配置")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(canApply ? (mode == 3 ? Color.orange : Color.blue)
                                       : Color.gray.opacity(0.35))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canApply || busy)
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    private var canApply: Bool {
        switch mode {
        case 0: return !bandText.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: return !freqText.trimmingCharacters(in: .whitespaces).isEmpty
        case 2: return !cellBand.isEmpty && !cellFreq.isEmpty && !cellPci.isEmpty
        default: return true
        }
    }

    private func field(_ title: String, _ text: Binding<String>, _ ph: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(ph, text: text)
                .font(.system(size: 14))
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        }
    }

    private func hint(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 邻区

    private var neighborCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("附近小区")
                    .font(.system(size: 15, weight: .bold))
                if !neighbors.isEmpty {
                    Text("\(neighbors.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                Spacer()
                Button {
                    Haptic.light()
                    Task { await reload() }
                } label: {
                    HStack(spacing: 4) {
                        if loading {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 11))
                        }
                        Text("扫描").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(loading)
            }

            if neighbors.isEmpty {
                Text(loading ? "正在读取…" : "设备没有上报邻区，点右上角「扫描」再读一次。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                Text("5G 邻区 · \(neighbors.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                ForEach(neighbors) { c in
                    Button {
                        Haptic.light()
                        mode = 2
                        cellBand = c.band.filter { $0.isNumber }
                        cellFreq = c.arfcn
                        cellPci = c.pci
                    } label: {
                        HStack(spacing: 10) {
                            // 信号强度图标
                            ZStack {
                                Circle()
                                    .fill(signalColor(c.rsrpValue).opacity(0.14))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 14))
                                    .foregroundStyle(signalColor(c.rsrpValue))
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    Text(c.band + " · " + c.arfcn)
                                        .font(.system(size: 12.5, weight: .semibold))
                                    if isCurrent(c) {
                                        Text("当前")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.green)
                                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                                            .background(Capsule().fill(Color.green.opacity(0.15)))
                                    }
                                }
                                Text(cellDetail(c))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 6)

                            Text(c.rsrp.isEmpty ? "--" : c.rsrp + "dBm")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(signalColor(c.rsrpValue))
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Text("点任意一行 = 一键锁小区（频点 + PCI），会先询问一次。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    /// 是否当前小区
    private func isCurrent(_ c: HuaweiAPI.CellEntry) -> Bool {
        guard let sc = serving else { return false }
        return sc.pci == c.pci && sc.arfcn == c.arfcn
    }

    /// 详情行：PCI · SINR · RSRQ
    private func cellDetail(_ c: HuaweiAPI.CellEntry) -> String {
        var parts: [String] = ["PCI " + c.pci]
        if !c.bw.isEmpty { parts.append(c.bw) }
        if !c.sinr.isEmpty { parts.append("SINR " + c.sinr + "dB") }
        if !c.rsrq.isEmpty { parts.append("RSRQ " + c.rsrq + "dB") }
        return parts.joined(separator: " · ")
    }

    /// RSRP 分级配色
    private func signalColor(_ r: Double) -> Color {
        if r >= -85 { return Color(red: 0.15, green: 0.82, blue: 0.45) }
        if r >= -95 { return Color(red: 0.55, green: 0.80, blue: 0.35) }
        if r >= -105 { return Color(red: 0.98, green: 0.75, blue: 0.25) }
        if r >= -115 { return Color(red: 0.96, green: 0.55, blue: 0.25) }
        return Color(red: 0.94, green: 0.32, blue: 0.30)
    }

    // MARK: 动作

    private func reload() async {
        loading = true
        let c = await HuaweiAPI.shared.fetchLockFreq()
        // nrCells 是 "band,freq,pci;..." 形式，邻区优先用它（开发者模式下的完整列表）
        if let nc = c["nrCells"], !nc.isEmpty {
            let cells = nc.components(separatedBy: ";").compactMap { seg -> HuaweiAPI.CellEntry? in
                let f = seg.components(separatedBy: ",")
                guard f.count >= 3 else { return nil }
                return HuaweiAPI.CellEntry(band: "N" + f[0], pci: f[2], arfcn: f[1],
                                           rsrp: "", rsrq: "", rssi: "", sinr: "", bw: "")
            }
            if !cells.isEmpty {
                current = c
                neighbors = cells
                serving = await HuaweiAPI.shared.fetchServingCell()
                loading = false
                return
            }
        }
        let n = await HuaweiAPI.shared.fetchNeighborCells()
        let sc = await HuaweiAPI.shared.fetchServingCell()
        current = c
        neighbors = n
        serving = sc
        loading = false
    }

    private func apply() async {
        busy = true
        let ok = await HuaweiAPI.shared.applyLock(
            mode: mode,
            band: bandText,
            freq: freqText,
            cellBand: cellBand,
            cellFreq: cellFreq,
            cellPci: cellPci)
        busy = false
        store.toast(ok ? "锁频配置已写入" : (HuaweiAPI.shared.lastErrorText.isEmpty
                                        ? "写入失败" : HuaweiAPI.shared.lastErrorText),
                    kind: ok ? .success : .error)
        if ok { await reload() }
    }
}
