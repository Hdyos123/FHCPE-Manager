import SwiftUI
import UserNotifications
import UIKit

// MARK: - 通知开关

enum NotifySwitch {
    private static let d = UserDefaults.standard

    static var flowLimit: Bool {
        get { d.object(forKey: "nt.flowLimit") as? Bool ?? true }
        set { d.set(newValue, forKey: "nt.flowLimit") }
    }
    static var offline: Bool {
        get { d.object(forKey: "nt.offline") as? Bool ?? true }
        set { d.set(newValue, forKey: "nt.offline") }
    }
    static var deviceSwitch: Bool {
        get { d.object(forKey: "nt.deviceSwitch") as? Bool ?? true }
        set { d.set(newValue, forKey: "nt.deviceSwitch") }
    }
    static var newSms: Bool {
        get { d.object(forKey: "nt.newSms") as? Bool ?? false }
        set { d.set(newValue, forKey: "nt.newSms") }
    }
    static var newClient: Bool {
        get { d.object(forKey: "nt.newClient") as? Bool ?? false }
        set { d.set(newValue, forKey: "nt.newClient") }
    }

    /// 上次已提醒的状态，避免重复
    static var lastOfflineNotify: String {
        get { d.string(forKey: "nt.lastOffline") ?? "" }
        set { d.set(newValue, forKey: "nt.lastOffline") }
    }
    static var lastSwitchNotify: String {
        get { d.string(forKey: "nt.lastSwitch") ?? "" }
        set { d.set(newValue, forKey: "nt.lastSwitch") }
    }
    static var lastSmsCount: Int {
        get { d.integer(forKey: "nt.lastSmsCount") }
        set { d.set(newValue, forKey: "nt.lastSmsCount") }
    }
    static var lastClientCount: Int {
        get { d.integer(forKey: "nt.lastClientCount") }
        set { d.set(newValue, forKey: "nt.lastClientCount") }
    }
}

// MARK: - 通知动作（需要二次确认的）

enum NotifyAction: Identifiable, Equatable {
    case switchDevice(String)        // 切换到指定 host
    case retryConnect
    case openSms
    case openTraffic
    case openClients

    var id: String {
        switch self {
        case .switchDevice(let h): return "switch-" + h
        case .retryConnect:        return "retry"
        case .openSms:             return "sms"
        case .openTraffic:         return "traffic"
        case .openClients:         return "clients"
        }
    }

    var confirmTitle: String {
        switch self {
        case .switchDevice(let h): return "切换到 " + h + "？"
        case .retryConnect:        return "重新连接设备？"
        case .openSms:             return "打开短信？"
        case .openTraffic:         return "查看流量统计？"
        case .openClients:         return "查看在线设备？"
        }
    }

    var confirmMessage: String {
        switch self {
        case .switchDevice:
            return "将断开当前设备并连接到新的设备，期间会有几秒无法刷新数据。"
        case .retryConnect:
            return "会重新登录当前设备。"
        default:
            return ""
        }
    }

    var confirmButton: String {
        switch self {
        case .switchDevice: return "切换"
        case .retryConnect: return "重连"
        default:            return "打开"
        }
    }
}

// MARK: - 通知中心

final class NotifyCenter: ObservableObject {
    static let shared = NotifyCenter()

    /// 待确认的动作
    @Published var pending: NotifyAction?

    private let center = UNUserNotificationCenter.current()

    private init() {}

    func bootstrap() {
        center.delegate = NotifyDelegate.shared
        registerCategories()
    }

    /// 申请权限
    func requestAuth() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func authStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { cont in
            center.getNotificationSettings { s in
                cont.resume(returning: s.authorizationStatus)
            }
        }
    }

    private func registerCategories() {
        let yes = UNNotificationAction(identifier: "ACT_YES", title: "确定", options: [.foreground])
        let no = UNNotificationAction(identifier: "ACT_NO", title: "忽略", options: [])

        let cats: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: "CAT_SWITCH",
                                   actions: [yes, no], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "CAT_OFFLINE",
                                   actions: [yes, no], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "CAT_SMS",
                                   actions: [yes, no], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "CAT_FLOW",
                                   actions: [yes, no], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "CAT_CLIENT",
                                   actions: [yes, no], intentIdentifiers: [], options: [])
        ]
        center.setNotificationCategories(cats)
    }

    /// 发一条本地通知
    func post(title: String, body: String, category: String, userInfo: [String: Any] = [:]) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.categoryIdentifier = category
        c.userInfo = userInfo
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        center.add(req, withCompletionHandler: nil)
    }

    /// 从通知动作解析出待确认操作
    func handleAction(category: String, actionID: String, userInfo: [String: Any]) {
        guard actionID == "ACT_YES" else { return }
        switch category {
        case "CAT_SWITCH":
            if let h = userInfo["host"] as? String {
                pending = .switchDevice(h)
            }
        case "CAT_OFFLINE":
            pending = .retryConnect
        case "CAT_SMS":
            pending = .openSms
        case "CAT_FLOW":
            pending = .openTraffic
        case "CAT_CLIENT":
            pending = .openClients
        default:
            break
        }
    }
}

// MARK: - 通知代理

final class NotifyDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifyDelegate()

    // App 在前台也展示通知
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let c = response.notification.request.content
        let cat = c.categoryIdentifier
        let act = response.actionIdentifier
        let info = c.userInfo
        Task { @MainActor in
            NotifyCenter.shared.handleAction(category: cat, actionID: act, userInfo: info)
        }
        completionHandler()
    }
}

// MARK: - 周期性检查（流量 / 在线数 / 新短信）

@MainActor
enum NotifyRunner {

    static func tick(_ store: CpeStore) async {
        guard store.isLoggedIn else { return }

        if NotifySwitch.flowLimit { checkFlow(store) }
        if NotifySwitch.newClient { checkClients(store) }
        if NotifySwitch.newSms { await checkSms(store) }
    }

    // 流量
    private static func checkFlow(_ store: CpeStore) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let day = f.string(from: Date())
        f.dateFormat = "yyyy-MM"
        let month = f.string(from: Date())

        let s = store.status
        let todayGB = (Double(s["todayTotal"]) ?? 0) / 1_073_741_824
        let monthGB = (Double(s["monthTotal"]) ?? 0) / 1_073_741_824

        let daily = FiberExtras.dailyLimitGB
        if daily > 0, todayGB >= daily, FiberExtras.warnedDay != day {
            FiberExtras.warnedDay = day
            NotifyCenter.shared.post(
                title: "今日流量已超限",
                body: String(format: "已用 %.2f GB，限额 %.0f GB", todayGB, daily),
                category: "CAT_FLOW")
        } else if daily > 0, todayGB >= daily * 0.8, FiberExtras.warnedDay != day + "-80" {
            FiberExtras.warnedDay = day + "-80"
            NotifyCenter.shared.post(
                title: "今日流量接近限额",
                body: String(format: "已用 %.2f GB，限额 %.0f GB（已到 80%%）", todayGB, daily),
                category: "CAT_FLOW")
        }

        let monthly = FiberExtras.monthlyLimitGB
        if monthly > 0, monthGB >= monthly, FiberExtras.warnedMonth != month {
            FiberExtras.warnedMonth = month
            NotifyCenter.shared.post(
                title: "本月流量已超限",
                body: String(format: "已用 %.2f GB，限额 %.0f GB", monthGB, monthly),
                category: "CAT_FLOW")
        }
    }

    // 在线设备数
    private static func checkClients(_ store: CpeStore) {
        let n: Int
        if store.isFiberHome { n = store.hosts.count }
        else { n = Int(store.status["online"]) ?? 0 }

        let last = NotifySwitch.lastClientCount
        if last > 0, n > last {
            NotifyCenter.shared.post(
                title: "有新设备接入",
                body: "当前在线 \(n) 台（上次 \(last) 台）",
                category: "CAT_CLIENT")
        }
        NotifySwitch.lastClientCount = n
    }

    // 新短信
    private static func checkSms(_ store: CpeStore) async {
        var count = 0
        if store.isHuawei {
            count = await HuaweiAPI.shared.fetchSms().count
        } else if store.isFiberHome {
            count = await store.fetchSms().count
        } else {
            return   // OPPO 无短信接口
        }
        let last = NotifySwitch.lastSmsCount
        if last > 0, count > last {
            NotifyCenter.shared.post(
                title: "收到新短信",
                body: "新增 \(count - last) 条未读",
                category: "CAT_SMS")
        }
        NotifySwitch.lastSmsCount = count
    }
}

// MARK: - 设置页里的通知区块

struct NotifySection: View {
    @State private var flowLimit = NotifySwitch.flowLimit
    @State private var offline = NotifySwitch.offline
    @State private var deviceSwitch = NotifySwitch.deviceSwitch
    @State private var newSms = NotifySwitch.newSms
    @State private var newClient = NotifySwitch.newClient
    @State private var auth: UNAuthorizationStatus = .notDetermined
    @State private var dailyLimit = FiberExtras.dailyLimitGB
    @State private var monthlyLimit = FiberExtras.monthlyLimitGB

    var body: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: auth == .denied ? "bell.slash" : "bell.badge")
                    .font(.system(size: 14))
                    .foregroundStyle(auth == .denied ? Color.red : Color.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(authText)
                        .font(.system(size: 13, weight: .medium))
                    Text(authHint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if auth == .notDetermined {
                    Button("开启") {
                        NotifyCenter.shared.requestAuth()
                        Haptic.light()
                    }
                    .font(.system(size: 12, weight: .medium))
                }
            }

            row("流量超限提醒", "达到日/月额度时提醒", $flowLimit) { NotifySwitch.flowLimit = $0 }

            if flowLimit {
                HStack {
                    Text("每日额度").font(.system(size: 14))
                    Spacer()
                    TextField("0", value: $dailyLimit, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onChange(of: dailyLimit) { FiberExtras.dailyLimitGB = $0 }
                    Text("GB").foregroundStyle(.secondary).font(.system(size: 13))
                }
                HStack {
                    Text("每月额度").font(.system(size: 14))
                    Spacer()
                    TextField("0", value: $monthlyLimit, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onChange(of: monthlyLimit) { FiberExtras.monthlyLimitGB = $0 }
                    Text("GB").foregroundStyle(.secondary).font(.system(size: 13))
                }
            }
            row("设备断开提醒", "探测不到当前设备时提醒", $offline) { NotifySwitch.offline = $0 }
            row("检测到另一台设备", "Wi-Fi 切换后提醒并可直接切换", $deviceSwitch) { NotifySwitch.deviceSwitch = $0 }
            row("新短信提醒", "收到未读短信时提醒", $newSms) { NotifySwitch.newSms = $0 }
            row("有人接入提醒", "在线设备数增加时提醒", $newClient) { NotifySwitch.newClient = $0 }
        } header: {
            Text("通知")
        } footer: {
            Text("App 被系统挂起（锁屏或切到后台较久）时无法实时检测，此时只有流量限额这类定时提醒能收到。建议配合「屏幕常亮」分屏使用。")
        }
        .task {
            auth = await NotifyCenter.shared.authStatus()
        }
    }

    private func row(_ title: String, _ sub: String, _ binding: Binding<Bool>,
                     onChange: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(
            get: { binding.wrappedValue },
            set: { v in
                binding.wrappedValue = v
                onChange(v)
                Haptic.light()
                if v { NotifyCenter.shared.requestAuth() }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14))
                Text(sub).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .tint(.green)
    }

    private var authText: String {
        switch auth {
        case .authorized:   return "通知已开启"
        case .denied:       return "通知被关闭"
        case .provisional:  return "通知（静默）"
        default:            return "尚未开启通知"
        }
    }

    private var authHint: String {
        switch auth {
        case .authorized, .provisional: return "提醒会以横幅形式出现"
        case .denied:                   return "请到 系统设置 → 通知 → CPE管理 打开"
        default:                        return "点右侧「开启」授权"
        }
    }
}
