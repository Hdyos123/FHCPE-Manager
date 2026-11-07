import SwiftUI

/// 华为锁频页：频段 / 频点 / 锁小区 / 解除
struct HuaweiLockView: View {
    @EnvironmentObject var store: CpeStore

    @State private var mode = 0                 // 0 频段 1 频点 2 锁小区 3 解除
    @State private var current: [String: String] = [:]
    @State private var neighbors: [(band: String, pci: String, freq: String, rsrp: String)] = []
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
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("附近小区")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(neighbors.count) 条")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if neighbors.isEmpty {
                Text("设备没有上报邻区。邻区表只在信号搜索时才会被填上。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(neighbors.enumerated()), id: \.offset) { _, c in
                    Button {
                        Haptic.light()
                        mode = 2
                        cellBand = c.band
                        cellFreq = c.freq
                        cellPci = c.pci
                    } label: {
                        HStack(spacing: 8) {
                            Text("B\(c.band)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.12)))
                            Text("PCI \(c.pci)")
                                .font(.system(size: 11.5))
                            Spacer()
                            Text("\(c.rsrp) dBm")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    // MARK: 动作

    private func reload() async {
        loading = true
        let c = await HuaweiAPI.shared.fetchLockFreq()
        let n = await HuaweiAPI.shared.fetchNeighborCells()
        current = c
        neighbors = n
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
