import SwiftUI

/// 华为锁频页：当前锁定横幅 + 三 Tab + 附近小区 + 锁定配置
struct HuaweiLockView: View {
    @EnvironmentObject var store: CpeStore

    @State private var tab = 1                      // 0 网络首选 1 锁频 2 天线
    @State private var loading = false
    @State private var busy = false

    @State private var lockedBands: [String] = []   // 当前锁的频段
    @State private var lockedCells: [String] = []   // 当前锁的小区 "n78 627264"
    @State private var nbrCells: [HuaweiAPI.CellEntry] = []
    @State private var serving: HuaweiAPI.CellEntry?

    // 网络首选
    @State private var preferNet = "auto"           // auto / 5G / 4G
    @State private var nrMode = "SA"

    // 锁频配置
    @State private var lockMode = 0                 // 0 不锁 1 锁频点 2 锁小区 3 锁频段
    @State private var bandText = ""
    @State private var freqText = ""
    @State private var cellBand = "n78"
    @State private var cellFreq = "627264"
    @State private var cellPci = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                lockedBanner
                tabBar

                switch tab {
                case 0: netPreferCard
                case 1:
                    neighborCard
                    lockConfigCard
                default: antennaCard
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 96)
        }
        .background(GlassListBackground())
        .refreshable { await reload() }
        .onAppear { Task { await reload() } }
    }
}

// MARK: - 当前锁定横幅
private extension HuaweiLockView {
    var lockedBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("当前锁定")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                Spacer()
            }

            let txt = lockedText
            Text(txt)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(txt == "未锁定" ? Color.secondary : Color.green)
                .lineLimit(1)

            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 18)
    }

    var lockedText: String {
        var parts: [String] = []
        parts.append(contentsOf: lockedBands.map { "N\($0)" })
        parts.append(contentsOf: lockedCells)
        if parts.isEmpty { return "未锁定" }
        return parts.joined(separator: " ")
    }

    var subtitle: String {
        let cellPart = lockedCells.isEmpty ? "未锁小区" : "\(lockedCells.count) 个小区"
        let bandPart = lockedBands.isEmpty ? "未锁频段" : "N\(lockedBands.joined(separator: "/N"))"
        return "5G \(cellPart) · 4G 不锁定 · 当前制式 自动（4G / 5G）"
    }
}

// MARK: - Tab
private extension HuaweiLockView {
    var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(["网络首选", "锁频", "天线设置"].enumerated()), id: \.offset) { i, t in
                Button {
                    Haptic.light()
                    withAnimation(.easeOut(duration: 0.18)) { tab = i }
                } label: {
                    Text(t)
                        .font(.system(size: 13, weight: tab == i ? .semibold : .regular))
                        .foregroundStyle(tab == i ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(tab == i ? Color.primary.opacity(0.10) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// MARK: - 网络首选
private extension HuaweiLockView {
    var netPreferCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                Text("网络首选方式")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
                Spacer()
            }

            Text(preferNet == "auto" ? "自动" : (preferNet == "5G" ? "仅 5G" : "仅 4G"))
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.blue)

            Text("5G 制式 \(nrMode) · 这两项改完都会让设备重新注册，短暂断网。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            Divider().opacity(0.3)

            Text("首选接入方式")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach([("自动", "auto"), ("5G", "5G"), ("4G", "4G")], id: \.0) { t, v in
                    Button {
                        Haptic.light()
                        preferNet = v
                    } label: {
                        Text(t)
                            .font(.system(size: 13, weight: preferNet == v ? .semibold : .regular))
                            .foregroundStyle(preferNet == v ? .white : Color.primary.opacity(0.7))
                            .frame(maxWidth: .infinity).frame(height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(preferNet == v ? Color.blue.opacity(0.85) : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("决定设备优先驻留哪一种网络。选「仅 5G」或「仅 4G」之后，下面另一个制式的锁频配置就不再提交了。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary.opacity(0.8))

            Text("5G 制式")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["SA", "NSA", "SA+NSA", "仅 4G"], id: \.self) { m in
                        Button {
                            Haptic.light()
                            nrMode = m
                        } label: {
                            Text(m)
                                .font(.system(size: 12.5, weight: nrMode == m ? .semibold : .regular))
                                .foregroundStyle(nrMode == m ? .white : Color.primary.opacity(0.7))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(
                                    Capsule().fill(nrMode == m ? Color.blue.opacity(0.85) : Color.primary.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                Task { await applyNetMode() }
            } label: {
                Text(busy ? "提交中…" : "应用网络首选")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.blue.opacity(busy ? 0.4 : 0.85))
                    )
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
        .padding(16)
        .glassCard(radius: 20)
    }
}

// MARK: - 天线
private extension HuaweiLockView {
    var antennaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("天线设置 · 不可用")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text("不支持")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.secondary)

            Text("这台设备的固件没开放天线设置，网页后台里那一块同样不会显示。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            Divider().opacity(0.3)

            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("这台设备没开放天线设置")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 24)
        }
        .padding(16)
        .glassCard(radius: 20)
    }
}

// MARK: - 附近小区
private extension HuaweiLockView {
    var neighborCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部
            HStack(spacing: 6) {
                Text("附近小区")
                    .font(.system(size: 16, weight: .bold))
                Text("\(nbrCells.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                Spacer()
                Button {
                    Haptic.light()
                    Task { await reload() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 10))
                        Text("扫描")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

            if loading && nbrCells.isEmpty {
                ProgressView().padding(.vertical, 30)
            } else if nbrCells.isEmpty {
                Text("没有扫描到邻区，点右上角「扫描」再试")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 20)
            } else {
                Text("5G 邻区 · \(nbrCells.count)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 6)

                ForEach(Array(nbrCells.enumerated()), id: \.offset) { _, c in
                    neighborRow(c)
                }
            }

            // 4G 邻区提示
            VStack(alignment: .leading, spacing: 4) {
                Text("4G 邻区")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("设备没有上报 4G 邻区。点右上角「扫描」再读一次。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 16).padding(.top, 12)

            Text("点任意一行 = 一键锁区：把那条小区写成「锁小区」（频点 + PCI），会先问一次。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary.opacity(0.6))
                .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .glassCard(radius: 20)
    }

    func neighborRow(_ c: HuaweiAPI.CellEntry) -> some View {
        let isCur = serving.map { $0.pci == c.pci } ?? false
        let v = Double(c.rsrp) ?? -140
        let col = rsrpColor(v)

        return Button {
            Haptic.light()
            lockMode = 2
            cellBand = c.band.lowercased()
            cellFreq = c.arfcn
            cellPci = c.pci
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(col.opacity(0.16)).frame(width: 30, height: 30)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(col)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(c.band.lowercased()) · \(c.arfcn)")
                            .font(.system(size: 13.5, weight: .semibold))
                        if isCur {
                            Text("当前")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.14)))
                        }
                    }
                    HStack(spacing: 6) {
                        Text("PCI \(c.pci)")
                        if !c.bw.isEmpty { Text("· \(c.bw)") }
                        if !c.sinr.isEmpty { Text("· SINR \(c.sinr)") }
                        if !c.rsrq.isEmpty { Text("· RSRQ \(c.rsrq)") }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text(c.rsrp.isEmpty ? "--" : c.rsrp)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(col)
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func rsrpColor(_ v: Double) -> Color {
        if v >= -85 { return .green }
        if v >= -95 { return .yellow }
        if v >= -105 { return .orange }
        return .red
    }
}

// MARK: - 5G NR 锁定配置
private extension HuaweiLockView {
    var lockConfigCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("5G NR 锁定配置")
                    .font(.system(size: 16, weight: .bold))
                Text("5")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                Spacer()
            }

            // 模式选择
            HStack(spacing: 6) {
                ForEach([(0, "不锁定"), (1, "锁频点"), (2, "锁小区"), (3, "锁频段")], id: \.0) { i, t in
                    Button {
                        Haptic.light()
                        lockMode = i
                    } label: {
                        Text(t)
                            .font(.system(size: 12, weight: lockMode == i ? .semibold : .regular))
                            .foregroundStyle(lockMode == i ? .white : Color.primary.opacity(0.7))
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(lockMode == i ? Color.blue.opacity(0.85) : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            switch lockMode {
            case 1:
                fieldBox("锁频点（如 627264）", text: $freqText)
            case 2:
                HStack(spacing: 8) {
                    fieldBox("频段", text: $cellBand)
                    fieldBox("频点", text: $cellFreq)
                    fieldBox("PCI", text: $cellPci)
                }
            case 3:
                fieldBox("锁频段（如 78,41,1）", text: $bandText)
            default:
                Text("不锁定：设备可自动选择任意频段与小区。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            if let s = serving {
                HStack(spacing: 8) {
                    Text("当前服务小区")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("\(s.band.lowercased()) · \(s.arfcn) · PCI \(s.pci)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.blue)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04)))
            }

            Button {
                Task { await applyLock() }
            } label: {
                Text(busy ? "提交中…" : "锁定 N78 · 627264 · PCI \(cellPci.isEmpty ? "--" : cellPci)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.blue.opacity(busy ? 0.4 : 0.85))
                    )
            }
            .buttonStyle(.plain)
            .disabled(busy)

            Text("锁频后设备会重新注册，短暂断网。锁定不存在的频点可能完全上不了网，请确认后再提交。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(16)
        .glassCard(radius: 20)
    }

    func fieldBox(_ ph: String, text: Binding<String>) -> some View {
        TextField(ph, text: text)
            .font(.system(size: 13))
            .keyboardType(.numbersAndPunctuation)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
    }
}

// MARK: - 动作
private extension HuaweiLockView {
    func reload() async {
        loading = true
        defer { loading = false }

        let lock = await HuaweiAPI.shared.fetchLockFreq()
        if let mode = lock["nrLockMode"], let m = Int(mode) { lockMode = m }
        if let bands = lock["nrBands"], !bands.isEmpty {
            lockedBands = bands.components(separatedBy: ",").filter { !$0.isEmpty }
        } else { lockedBands = [] }
        if let cells = lock["nrCells"], !cells.isEmpty {
            lockedCells = cells.components(separatedBy: ";").compactMap { seg -> String? in
                let f = seg.components(separatedBy: ",")
                guard f.count >= 2 else { return nil }
                return "n\(f[0]) \(f[1])"
            }
        } else { lockedCells = [] }

        serving = await HuaweiAPI.shared.fetchServingCell()
        nbrCells = await HuaweiAPI.shared.fetchNeighborCells()
    }

    func applyLock() async {
        busy = true
        defer { busy = false }

        var ok = false
        switch lockMode {
        case 0:
            ok = await HuaweiAPI.shared.lockNR(mode: 3, band: "", freq: "", cellBand: "", cellFreq: "", cellPci: "")
        case 1:
            ok = await HuaweiAPI.shared.lockNR(mode: 1, band: "", freq: freqText,
                                               cellBand: "", cellFreq: "", cellPci: "")
        case 2:
            ok = await HuaweiAPI.shared.lockNR(mode: 2, band: "", freq: "",
                                               cellBand: cellBand, cellFreq: cellFreq, cellPci: cellPci)
        default:
            ok = await HuaweiAPI.shared.lockNR(mode: 0, band: bandText, freq: "",
                                               cellBand: "", cellFreq: "", cellPci: "")
        }

        store.toast(ok ? "已提交锁定配置，设备将重新注册" : "提交失败，请稍后再试",
                    kind: ok ? .success : .error)
        if ok { await reload() }
    }

    func applyNetMode() async {
        busy = true
        defer { busy = false }
        let ok = await HuaweiAPI.shared.setNetPrefer(preferNet)
        store.toast(ok ? "已切换网络首选方式" : "切换失败", kind: ok ? .success : .error)
    }
}
