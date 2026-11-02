import SwiftUI

// MARK: - 锁频

struct LockBandView: View {
    @EnvironmentObject var store: CpeStore

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
            WideAdapter(maxWidth: 560) {
            ScrollView {
                VStack(spacing: 12) {
                    currentCard
                    modeCard
                    bandGridCard
                    carrierCard
                    applyBar
                    hints
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("锁频")
            }
            .background(GlassListBackground())
            .task { loadCurrent() }
            .alert("确认操作", isPresented: $showConfirm) {
                Button("取消", role: .cancel) { }
                Button("确定") {
                    Haptic.medium()
                    applyPending()
                }
            } message: {
                Text(pendingAction == "band"
                     ? "将锁定频段，网络会重新注册并短暂断网。确定继续？"
                     : "将锁定运营商，网络会重新注册。确定继续？")
            }
        }
    }

    // MARK: 当前状态

    private var currentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("当前状态")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(lockEnabled ? "已锁定" : "自动")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(lockEnabled ? .orange : .secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill((lockEnabled ? Color.orange : Color.secondary).opacity(0.12)))
            }

            HStack(spacing: 0) {
                statItem("频段", "N" + (s["band"].isEmpty ? "--" : s["band"]))
                Divider().frame(height: 26)
                statItem("PCI", s["pci"].isEmpty ? "--" : s["pci"])
                Divider().frame(height: 26)
                statItem("带宽", s["bw"].isEmpty ? "--" : s["bw"])
            }

            if lockEnabled {
                Text("已锁：5G \(selectedNR.isEmpty ? "全部" : selectedNR.sorted().map { "n\($0)" }.joined(separator: " "))"
                     + " · 4G \(selectedLTE.isEmpty ? "全部" : selectedLTE.sorted().map { "B\($0)" }.joined(separator: " "))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    private func statItem(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .bold))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 模式

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("锁定方式")
                .font(.system(size: 13, weight: .semibold))

            Picker("", selection: $lockEnabled) {
                Text("自动（不锁定）").tag(false)
                Text("频段锁定").tag(true)
            }
            .pickerStyle(.segmented)

            Text(lockEnabled
                 ? "设备只在你勾选的频段上工作。勾得越少越容易失去信号。"
                 : "由基站自由调度，信号变化时自动切换。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    // MARK: 频段网格

    private var bandGridCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            group("5G NR", bands: nrBands, selected: selectedNR, prefix: "n") { toggleNR($0) }
            Divider().opacity(0.4)
            group("4G LTE", bands: lteBands, selected: selectedLTE, prefix: "B") { toggleLTE($0) }
        }
        .padding(14)
        .glassCard(radius: 18)
        .opacity(lockEnabled ? 1 : 0.5)
        .allowsHitTesting(lockEnabled)
    }

    private func group(_ title: String, bands: [Int], selected: Set<Int>,
                       prefix: String, onTap: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(selected.count)/\(bands.count)")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4),
                      spacing: 7) {
                ForEach(bands, id: \.self) { b in
                    let on = selected.contains(b)
                    Button {
                        Haptic.selection()
                        onTap(b)
                    } label: {
                        Text(prefix + "\(b)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(on ? .white : Color.primary.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(on ? Color.blue : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 运营商

    private var carrierCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("运营商锁定", isOn: $carrierEnabled)
                .font(.system(size: 13, weight: .semibold))

            if carrierEnabled {
                HStack {
                    Text("运营商代码").font(.system(size: 12))
                    Spacer()
                    TextField("46001", text: $carrierSerial)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .font(.system(size: 13))
                }
                Text("联通 46001 · 移动 46000 · 电信 46011")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)

                Button {
                    pendingAction = "carrier"
                    showConfirm = true
                } label: {
                    Text("应用运营商锁定")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    // MARK: 提交

    private var applyBar: some View {
        Button {
            pendingAction = "band"
            showConfirm = true
        } label: {
            HStack(spacing: 6) {
                if busy { ProgressView().tint(.white).scaleEffect(0.8) }
                Text(busy ? "应用中…" : (lockEnabled ? "写入锁频配置" : "解除全部锁定"))
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(lockEnabled ? Color.blue : Color.orange)
            )
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private var hints: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("锁定后设备会重新搜网，期间断线十几秒", systemImage: "info.circle")
            Label("如果锁定的频段当前不可用，会一直没有信号", systemImage: "exclamationmark.triangle")
            Label("锁错了回到这一页选「自动」再写入即可恢复", systemImage: "arrow.uturn.backward")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func toggleNR(_ b: Int) {
        if selectedNR.contains(b) { selectedNR.remove(b) } else { selectedNR.insert(b) }
    }

    private func toggleLTE(_ b: Int) {
        if selectedLTE.contains(b) { selectedLTE.remove(b) } else { selectedLTE.insert(b) }
    }

    private func loadCurrent() {
        lockEnabled = store.status["lockbandEn"] == "1"
        carrierEnabled = store.status["carrierLockEn"] == "1"
        carrierSerial = store.status["carrierLockNum"]

        let nr = store.status["lockbandNr"]
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" })
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        selectedNR = Set(nr)

        let lte = store.status["lockbandLte"]
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" })
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        selectedLTE = Set(lte)
    }

    private func applyPending() {
        busy = true
        Task {
            defer { busy = false }
            do {
                if pendingAction == "band" {
                    let ok = await store.applyBandLock(
                        enable: lockEnabled,
                        nr: Array(selectedNR).sorted(),
                        lte: Array(selectedLTE).sorted())
                    store.toast(ok ? "频段锁定已应用" : "应用失败，请检查连接",
                                       kind: ok ? .success : .error)
                } else {
                    let ok = await store.applyCarrierLock(
                        enable: carrierEnabled, serial: carrierSerial)
                    store.toast(ok ? "运营商锁定已应用" : "应用失败，请检查连接",
                                       kind: ok ? .success : .error)
                }
            } catch {
                store.errorText = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }
}

// MARK: - 短信

struct SmsView: View {
    @EnvironmentObject var store: CpeStore
    @State private var list: [CpeSms] = []
    @State private var loading = false
    @State private var showCompose = false
    @State private var composeTo = ""
    @State private var composeText = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            WideAdapter(maxWidth: 560) {
                ScrollView {
                    VStack(spacing: 10) {
                        if loading && list.isEmpty {
                            ProgressView().padding(.top, 60)
                        } else if list.isEmpty {
                            emptyView
                        } else {
                            header
                            ForEach(list) { m in
                                row(m)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await load() }
                .navigationTitle("短信")
            }
            .background(GlassListBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptic.light()
                        composeTo = ""
                        composeText = ""
                        showCompose = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showCompose) {
                composeSheet.presentationDetents([.medium])
            }
            .task { await load() }
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full")
                .font(.system(size: 11))
            Text("共 \(list.count) 条")
                .font(.system(size: 11.5))
            Spacer()
            if !codesCount.isEmpty {
                Text("\(codesCount) 条含验证码")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.blue)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var codesCount: [String] {
        list.compactMap { verificationCode($0.content) }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "message")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("收件箱是空的")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("下拉可重新读取")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(.top, 70)
    }

    // MARK: 单条

    private func row(_ m: CpeSms) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                // 首字头像
                Text(avatarText(m.sender))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(avatarColor(m.sender)))

                VStack(alignment: .leading, spacing: 1) {
                    Text(m.sender.isEmpty ? "未知号码" : m.sender)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(m.time.isEmpty ? "时间未知" : shortTime(m.time))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(m.content)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let code = verificationCode(m.content) {
                Button {
                    Haptic.success()
                    UIPasteboard.general.string = code
                    store.toast("已复制验证码 \(code)", kind: .success)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                        Text("复制验证码 \(code)")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.blue.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .glassCard(radius: 16)
        .contextMenu {
            Button {
                UIPasteboard.general.string = m.content
                store.toast("已复制内容", kind: .success)
            } label: { Label("复制内容", systemImage: "doc.on.doc") }

            Button {
                UIPasteboard.general.string = m.sender
                store.toast("已复制号码", kind: .success)
            } label: { Label("复制号码", systemImage: "phone") }

            Button {
                composeTo = m.sender
                composeText = ""
                showCompose = true
            } label: { Label("回复", systemImage: "arrowshape.turn.up.left") }
        }
    }

    private func avatarText(_ sender: String) -> String {
        let t = sender.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return "?" }
        return String(t.prefix(1))
    }

    private func avatarColor(_ sender: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .teal, .pink]
        let h = abs(sender.hashValue)
        return palette[h % palette.count]
    }

    private func shortTime(_ s: String) -> String {
        // 2024-01-02 12:34:56 → 01-02 12:34
        let chars = Array(s)
        if chars.count >= 16 {
            let a = String(chars[5..<10])
            let b = String(chars[11..<16])
            return a + " " + b
        }
        return s
    }

    /// 从短信里提取 4-8 位验证码
    private func verificationCode(_ s: String) -> String? {
        let lower = s.lowercased()
        guard lower.contains("验证码") || lower.contains("校验码")
                || lower.contains("动态码") || lower.contains("验证代码")
                || lower.contains("code") else { return nil }
        guard let re = try? NSRegularExpression(pattern: "(?<![0-9])([0-9]{4,8})(?![0-9])") else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: range),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    // MARK: 发送

    private var composeSheet: some View {
        NavigationStack {
            Form {
                Section("接收号码") {
                    TextField("手机号", text: $composeTo)
                        .keyboardType(.phonePad)
                }
                Section("内容") {
                    TextField("短信内容", text: $composeText, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Button {
                        sendSms()
                    } label: {
                        HStack {
                            Spacer()
                            if sending { ProgressView().padding(.trailing, 6) }
                            Text(sending ? "发送中…" : "发送")
                            Spacer()
                        }
                    }
                    .disabled(sending || composeTo.isEmpty || composeText.isEmpty)
                }
            }
            .navigationTitle("发送短信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showCompose = false }
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        list = await store.fetchSms()
    }

    private func sendSms() {
        sending = true
        Task {
            let ok = await store.sendSms(to: composeTo, text: composeText)
            sending = false
            store.toast(ok ? "短信已发送" : "发送失败，请检查信号与号码",
                        kind: ok ? .success : .error)
            if ok {
                composeTo = ""
                composeText = ""
                showCompose = false
                await load()
            }
        }
    }
}
