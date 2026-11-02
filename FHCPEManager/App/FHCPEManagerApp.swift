import SwiftUI
import UIKit

@main
struct FHCPEManagerApp: App {
    @StateObject private var store = CpeStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: CpeStore
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var notify = NotifyCenter.shared
    @State private var pendingAction: NotifyAction?

    var body: some View {
        ZStack {
            // 隐藏的 WKWebView 宿主：负责保持 CPE 会话
            BridgeHost()
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)

            // OPPO CPE 的会话宿主
            // WebKit 规则：视图必须「在窗口内」且 alpha > 0，否则暂停 JS。
            // 所以：放在左下角、尺寸小、不加 opacity、不用 offset 移出屏幕。
            OppoHost()
                .frame(width: 2, height: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(false)
                .zIndex(-1)

            if store.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }

            // 顶部玻璃通知
            if let t = store.toastText {
                VStack {
                    GlassToast(text: t, kind: store.toastKind)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .padding(.top, 8)
                .allowsHitTesting(false)
                .zIndex(99)
                .animation(.spring(response: 0.38, dampingFraction: 0.8), value: store.toastText)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.isLoggedIn)
        .onAppear {
            NotifyCenter.shared.bootstrap()
            if NotifySwitch.flowLimit || NotifySwitch.offline
                || NotifySwitch.deviceSwitch || NotifySwitch.newSms
                || NotifySwitch.newClient {
                NotifyCenter.shared.requestAuth()
            }
            Task { await store.tryAutoLogin() }
            // 自愈定时器：每 5 秒检查轮询是否还活着（分屏挂边时系统可能挂起 Task）
            // 恢复屏幕常亮设置
            UIApplication.shared.isIdleTimerDisabled =
                UserDefaults.standard.bool(forKey: "keepAwake")
            // 自愈定时器：每 5 秒检查轮询是否还活着（分屏挂边时系统可能挂起 Task）
            Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                Task { @MainActor in store.ensurePollingAlive() }
            }

            // 每分钟检查：流量限额提醒 + 定时重启（仅烽火生效）
            FiberExtrasRunner.startMinuteTicker(store)

            // 通知检查：流量 / 在线数 / 新短信
            Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                Task { @MainActor in await NotifyRunner.tick(store) }
            }
        }
        .onChange(of: store.isLoggedIn) { ok in
            if ok { store.startPolling() } else { store.stopPolling() }
        }
        .onChange(of: notify.pending) { act in
            pendingAction = act
        }
        .alert(pendingAction?.confirmTitle ?? "",
               isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil; notify.pending = nil } }
               )) {
            Button("取消", role: .cancel) {
                pendingAction = nil; notify.pending = nil
            }
            Button(pendingAction?.confirmButton ?? "确定") {
                let a = pendingAction
                pendingAction = nil; notify.pending = nil
                Task { await handleNotifyAction(a, store: store) }
            }
        } message: {
            Text(pendingAction?.confirmMessage ?? "")
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                // 回到前台：取消待执行的会话释放，并重连
                FiberExtrasRunner.cancelPendingRelease()
                Task { await store.resumeFromBackground() }
            case .inactive:
                // 分屏挂边、下拉通知中心等：保持轮询，只补一次刷新
                Task { await store.fetchStatus() }
            case .background:
                // 真正进入后台：停止轮询节省资源
                store.stopPolling()
                // 烽火：可选的后台释放会话，腾出设备在线名额
                FiberExtrasRunner.scheduleReleaseIfNeeded(store)
            @unknown default:
                break
            }
        }
    }
}

/// 把 WKWebView 挂到 SwiftUI 视图树里
struct BridgeHost: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        CpeBridge.shared.attach(to: v)
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// 把 OPPO 的 WKWebView 挂到 SwiftUI 视图树里
struct OppoHost: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        OppoBridge.shared.attach(to: v)
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// 执行通知动作（已通过二次确认）
@MainActor
private func handleNotifyAction(_ a: NotifyAction?, store: CpeStore) async {
    guard let a else { return }
    switch a {
    case .switchDevice(let host):
        if let p = ProfileStore.loadAll().first(where: { $0.host == host }) {
            await store.switchTo(p)
        }
    case .retryConnect:
        await store.resumeFromBackground()
    default:
        break   // 打开类动作交给 Tab 切换处理
    }
}

struct MainTabView: View {
    @StateObject private var router = TabRouter()

    var body: some View {
        TabView(selection: $router.selection) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(0)

            SmsTab()
                .tabItem { Label("短信", systemImage: "message.fill") }
                .tag(1)

            ControlTab()
                .tabItem { Label("控制", systemImage: "slider.horizontal.3") }
                .tag(2)

            LockTab()
                .tabItem { Label("锁频", systemImage: "lock.fill") }
                .tag(3)

            ParamTab()
                .tabItem { Label("参数", systemImage: "doc.text") }
                .tag(4)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(5)
        }
        .environmentObject(router)
    }
}
