import SwiftUI

// MARK: - 华为设备设置（插在通用设置页里，仅华为显示）

struct HuaweiSettingsSection: View {
    @EnvironmentObject var store: CpeStore

    @State private var showPwd = false
    @State private var showFactory = false
    @State private var showLedTiming = false
    @State private var showDiag = false

    @AppStorage("hw.autoRelease") private var autoRelease = false
    @AppStorage("hw.releaseDelay") private var releaseDelay = 60

    var body: some View {
        Section {
            Toggle(isOn: $autoRelease) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("后台自动释放会话")
                    Text("切到后台超过设定时间自动注销，腾出在线名额")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.green)

            if autoRelease {
                Picker("释放延迟", selection: $releaseDelay) {
                    Text("30 秒").tag(30)
                    Text("1 分钟").tag(60)
                    Text("2 分钟").tag(120)
                    Text("5 分钟").tag(300)
                }
            }
        } header: {
            Text("会话")
        } footer: {
            if autoRelease {
                Text("设备的在线用户数上限很低，电脑要开网页后台时建议开启。")
            }
        }

        Section {
            Button {
                Haptic.light()
                showLedTiming = true
            } label: {
                HStack {
                    Text("信号灯定时")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }

            Button {
                Haptic.light()
                showPwd = true
            } label: {
                HStack {
                    Text("修改管理员密码")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }

            Button {
                Haptic.light()
                showDiag = true
            } label: {
                HStack {
                    Text("诊断与排障")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
        } header: {
            Text("设备")
        }

        Section {
            Button(role: .destructive) {
                Haptic.warning()
                showFactory = true
            } label: {
                Text("恢复出厂设置")
            }
        } footer: {
            Text("名称、密码、锁频等全部配置都会清空，且无法撤销。")
        }
        .sheet(isPresented: $showPwd) { HuaweiPasswordSheet() }
        .sheet(isPresented: $showLedTiming) { HuaweiLedSheet() }
        .sheet(isPresented: $showDiag) { HuaweiDiagSheet() }
        .alert("恢复出厂设置", isPresented: $showFactory) {
            Button("取消", role: .cancel) { }
            Button("恢复", role: .destructive) {
                Task {
                    let ok = await HuaweiAPI.shared.factoryReset()
                    store.toast(ok ? "恢复出厂指令已下发，设备大约一分钟后恢复"
                                   : "操作失败", kind: ok ? .success : .error)
                }
            }
        } message: {
            Text("名称、密码、锁频等全部配置都会清空，且无法撤销。\n\n设备重启期间所有终端都会断网。")
        }
    }
}

// MARK: - 改密码

struct HuaweiPasswordSheet: View {
    @EnvironmentObject var store: CpeStore
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var new1 = ""
    @State private var new2 = ""
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("输入现在的登录密码", text: $current)
                } header: { Text("当前密码") }

                Section {
                    SecureField("新密码", text: $new1)
                    SecureField("再输一次新密码", text: $new2)
                } header: { Text("新密码") }
                footer: {
                    Text("建议混合大小写字母与数字。修改后会用新密码重新登录一次，可能会短暂断开。")
                }

                if !error.isEmpty {
                    Section {
                        Text(error).font(.system(size: 12)).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Spacer()
                            if busy { ProgressView().padding(.trailing, 6) }
                            Text(busy ? "提交中…" : "修改密码")
                            Spacer()
                        }
                    }
                    .disabled(busy || current.isEmpty || new1.isEmpty)
                }
            }
            .navigationTitle("修改管理员密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func submit() {
        error = ""
        if new1 != new2 { error = "两次输入的新密码不一致"; return }
        if new1 == current { error = "新密码不能与当前密码相同"; return }
        if new1.count < 4 { error = "新密码至少 4 位"; return }

        busy = true
        Task {
            let ok = await HuaweiAPI.shared.changePassword(current: current, new: new1)
            busy = false
            if ok {
                store.toast("密码已修改，已用新密码重新登录", kind: .success)
                dismiss()
            } else {
                error = HuaweiAPI.shared.lastErrorText.isEmpty
                    ? "修改失败，请检查当前密码" : HuaweiAPI.shared.lastErrorText
            }
        }
    }
}

// MARK: - 信号灯定时

struct HuaweiLedSheet: View {
    @EnvironmentObject var store: CpeStore
    @Environment(\.dismiss) private var dismiss

    @State private var ledOn = true
    @State private var timingOn = false
    @State private var startTime = "22:00"
    @State private var endTime = "07:00"
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("机身信号灯", isOn: Binding(
                        get: { ledOn },
                        set: { ledOn = $0; setLed($0) }
                    ))
                } footer: {
                    Text("关闭后机身指示灯不再亮起。")
                }

                Section {
                    Toggle("定时熄灯", isOn: $timingOn)
                    if timingOn {
                        HStack {
                            Text("熄灯开始")
                            Spacer()
                            TextField("22:00", text: $startTime)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numbersAndPunctuation)
                                .frame(width: 70)
                        }
                        HStack {
                            Text("熄灯结束")
                            Spacer()
                            TextField("07:00", text: $endTime)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numbersAndPunctuation)
                                .frame(width: 70)
                        }
                    }
                } header: {
                    Text("定时")
                } footer: {
                    Text("到点自动熄灭机身指示灯。跨零点是允许的，例如 22:00 到 07:00 表示夜间熄灯、清晨恢复。")
                }

                Section {
                    Button {
                        save()
                    } label: {
                        HStack {
                            Spacer()
                            if busy { ProgressView().padding(.trailing, 6) }
                            Text("保存")
                            Spacer()
                        }
                    }
                    .disabled(busy)
                }
            }
            .navigationTitle("信号灯")
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
        // 从主状态推断灯是否亮
        ledOn = store.status["led"].isEmpty || store.status["led"] == "1"
    }

    private func setLed(_ on: Bool) {
        Task {
            _ = await HuaweiAPI.shared.setLed(on)
        }
    }

    private func save() {
        if timingOn && startTime >= endTime {
            // 允许跨零点，这里只提示不阻止
        }
        busy = true
        Task {
            let ok = await HuaweiAPI.shared.setLedTiming(enable: timingOn,
                                                          start: startTime,
                                                          end: endTime)
            busy = false
            store.toast(ok ? "信号灯时段已保存" : "保存失败", kind: ok ? .success : .error)
            if ok { dismiss() }
        }
    }
}

// MARK: - 诊断

struct HuaweiDiagSheet: View {
    @EnvironmentObject var store: CpeStore
    @Environment(\.dismiss) private var dismiss

    @State private var lines: [String] = []
    @State private var running = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        Task { await run() }
                    } label: {
                        HStack {
                            Spacer()
                            if running { ProgressView().padding(.trailing, 6) }
                            Text(running ? "检测中…" : "开始诊断")
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue))
                        .foregroundStyle(.white)
                    }
                    .disabled(running)

                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                        Text(l)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(l.hasPrefix("✗") ? .red : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
            }
            .navigationTitle("诊断与排障")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
        }
    }

    private func run() async {
        running = true
        lines = []
        let api = HuaweiAPI.shared
        let host = store.activeProfile?.host ?? ""

        lines.append("设备：\(host)")
        lines.append("")

        lines.append("① 检查会话接口")
        if let _ = try? await api.request("GET", "/api/webserver/SesTokInfo", body: nil) {
            lines.append("   ✓ SesTokInfo 正常")
        } else {
            lines.append("   ✗ SesTokInfo 无响应")
            running = false
            return
        }

        lines.append("② 检查登录状态")
        if let s = try? await api.lockState() {
            lines.append(s.locked ? "   ✗ 设备已锁定，等 \(s.minutes) 分钟" : "   ✓ 未锁定")
        }

        lines.append("③ 读取设备信息")
        let info = await api.fetchOverview()
        if info.isEmpty {
            lines.append("   ✗ 读不到数据，会话可能已失效")
        } else {
            lines.append("   ✓ 读到 \(info.count) 项")
            if let m = info["model"] { lines.append("   型号：\(m)") }
            if let r = info["rsrp"] { lines.append("   RSRP：\(r) dBm") }
            if let n = info["netmode"] { lines.append("   网络：\(n)") }
        }

        lines.append("④ 检查各接口")
        let probes: [(String, String)] = [
            ("信号", "/api/device/signal"),
            ("状态", "/api/monitoring/status"),
            ("流量", "/api/monitoring/traffic-statistics"),
            ("短信", "/api/sms/sms-count"),
            ("在线设备", "/api/system/HostInfo"),
            ("锁频", "/api/net/lock-freq"),
            ("WLAN", "/api/wlan/multi-basic-settings"),
            ("天线", "/api/device/antenna_type")
        ]
        for (name, path) in probes {
            if let node = try? await api.request("GET", path, body: nil) {
                if node.find("error")?.text("code") != nil,
                   node.find("error")?.text("code") != "0" {
                    lines.append("   ✗ \(name)：不支持")
                } else {
                    lines.append("   ✓ \(name)")
                }
            } else {
                lines.append("   ✗ \(name)：无响应")
            }
        }

        running = false
    }
}
