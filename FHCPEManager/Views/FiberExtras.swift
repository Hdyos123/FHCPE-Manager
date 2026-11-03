import SwiftUI
import UserNotifications

// MARK: - 烽火增强设置存储

/// 只对烽火生效的本地设置，不涉及 OPPO / 华为
enum FiberExtras {
    private static let d = UserDefaults.standard

    // 后台自动释放会话
    static var autoRelease: Bool {
        get { d.object(forKey: "fib.autoRelease") as? Bool ?? false }
        set { d.set(newValue, forKey: "fib.autoRelease") }
    }
    static var releaseDelay: Int {
        get { let v = d.integer(forKey: "fib.releaseDelay"); return v > 0 ? v : 60 }
        set { d.set(newValue, forKey: "fib.releaseDelay") }
    }

    // 流量限额
    static var limitOn: Bool {
        get { d.object(forKey: "fib.limitOn") as? Bool ?? false }
        set { d.set(newValue, forKey: "fib.limitOn") }
    }
    static var dailyLimitGB: Double {
        get { d.double(forKey: "fib.dailyLimitGB") }
        set { d.set(newValue, forKey: "fib.dailyLimitGB") }
    }
    static var monthlyLimitGB: Double {
        get { d.double(forKey: "fib.monthlyLimitGB") }
        set { d.set(newValue, forKey: "fib.monthlyLimitGB") }
    }

    // 定时重启
    static var rebootOn: Bool {
        get { d.object(forKey: "fib.rebootOn") as? Bool ?? false }
        set { d.set(newValue, forKey: "fib.rebootOn") }
    }
    static var rebootTime: String {
        get { d.string(forKey: "fib.rebootTime") ?? "04:00" }
        set { d.set(newValue, forKey: "fib.rebootTime") }
    }

    /// 记录今天是否已经执行过（避免同一分钟内重复触发）
    static var lastRebootDay: String {
        get { d.string(forKey: "fib.lastRebootDay") ?? "" }
        set { d.set(newValue, forKey: "fib.lastRebootDay") }
    }

    // 限额提醒去重（同一天/同一月只提醒一次）
    static var dailyWarnedKey: String {
        get { d.string(forKey: "fib.dailyWarned") ?? "" }
        set { d.set(newValue, forKey: "fib.dailyWarned") }
    }
    static var monthlyWarnedKey: String {
        get { d.string(forKey: "fib.monthlyWarned") ?? "" }
        set { d.set(newValue, forKey: "fib.monthlyWarned") }
    }
    static var warnedDay: String {
        get { d.string(forKey: "fib.warnedDay") ?? "" }
        set { d.set(newValue, forKey: "fib.warnedDay") }
    }
    static var warnedMonth: String {
        get { d.string(forKey: "fib.warnedMonth") ?? "" }
        set { d.set(newValue, forKey: "fib.warnedMonth") }
    }

    /// 是否在后台被释放了会话
    static var sessionReleased: Bool {
        get { d.bool(forKey: "fib.sessionReleased") }
        set { d.set(newValue, forKey: "fib.sessionReleased") }
    }
}

// MARK: - 设置页里的「烽火增强」区块

struct FiberExtrasSection: View {
    @EnvironmentObject var store: CpeStore

    @State private var autoRelease = FiberExtras.autoRelease
    @State private var releaseDelay = FiberExtras.releaseDelay
    @State private var rebootOn = FiberExtras.rebootOn
    @State private var rebootTime = FiberExtras.rebootTime
    @State private var showFactory = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { autoRelease },
                set: { v in
                    autoRelease = v
                    FiberExtras.autoRelease = v
                    Haptic.light()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("后台自动释放会话")
                    Text("切到后台超过设定时间自动断开，腾出设备在线名额")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if autoRelease {
                Picker("释放延迟", selection: Binding(
                    get: { releaseDelay },
                    set: { releaseDelay = $0; FiberExtras.releaseDelay = $0 }
                )) {
                    Text("30 秒").tag(30)
                    Text("1 分钟").tag(60)
                    Text("2 分钟").tag(120)
                    Text("5 分钟").tag(300)
                }
            }
        } header: {
            Text("会话")
        }

        Section {
            Toggle(isOn: Binding(
                get: { rebootOn },
                set: { v in
                    rebootOn = v
                    FiberExtras.rebootOn = v
                    Haptic.light()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("定时重启")
                    Text("每天到点重启一次，需 App 在运行")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if rebootOn {
                HStack {
                    Text("重启时间")
                    Spacer()
                    TextField("04:00", text: $rebootTime)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        .onChange(of: rebootTime) { FiberExtras.rebootTime = $0 }
                }
            }
        } header: {
            Text("维护")
        } footer: {
            if rebootOn {
                Text("iOS 不允许 App 在后台定时执行，所以只有 App 打开时才会触发。建议配合「屏幕常亮」使用。")
            }
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
        .alert("恢复出厂设置", isPresented: $showFactory) {
            Button("取消", role: .cancel) { }
            Button("恢复", role: .destructive) {
                Task {
                    let ok = await store.factoryReset()
                    store.toast(ok ? "恢复出厂指令已下发" : "操作失败",
                                kind: ok ? .success : .error)
                }
            }
        } message: {
            Text("名称、密码、锁频等全部配置都会清空，且无法撤销。\n\n设备重启期间所有终端都会断网。")
        }
    }

}

// MARK: - 烽火扩展的运行时检查（限额 / 定时重启）

@MainActor
enum FiberExtrasRunner {
    private static var ticker: Timer?
    private static var releaseTask: Task<Void, Never>?

    /// 启动每分钟检查
    static func startMinuteTicker(_ store: CpeStore) {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in tick(store) }
        }
    }

    /// 进入后台后按设定延迟释放会话
    static func scheduleReleaseIfNeeded(_ store: CpeStore) {
        guard store.isFiberHome, FiberExtras.autoRelease else { return }
        let delay = FiberExtras.releaseDelay
        releaseTask?.cancel()
        releaseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            // 仍在后台才释放
            guard UIApplication.shared.applicationState != .active else { return }
            store.releaseSessionForBackground()
        }
    }

    /// 回到前台时取消待执行的释放
    static func cancelPendingRelease() {
        releaseTask?.cancel()
        releaseTask = nil
    }

    /// 每分钟调用一次
    static func tick(_ store: CpeStore) {
        guard store.isFiberHome, store.isLoggedIn else { return }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let day = f.string(from: Date())
        f.dateFormat = "yyyy-MM"
        let month = f.string(from: Date())

        // ② 定时重启
        guard FiberExtras.rebootOn else { return }
        f.dateFormat = "HH:mm"
        let now = f.string(from: Date())
        guard now == FiberExtras.rebootTime, FiberExtras.lastRebootDay != day else { return }
        FiberExtras.lastRebootDay = day

        Task {
            let ok = await store.reboot()
            store.toast(ok ? "定时重启指令已发送" : "定时重启失败", kind: ok ? .success : .error)
        }
    }

    private static func notify(_ title: String, _ body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let req = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
            center.add(req, withCompletionHandler: nil)
        }
    }
}
