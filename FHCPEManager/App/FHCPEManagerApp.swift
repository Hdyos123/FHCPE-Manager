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

    var body: some View {
        ZStack {
            // 隐藏的 WKWebView 宿主：负责保持 CPE 会话
            BridgeHost()
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)

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
            Task { await store.tryAutoLogin() }
            // 自愈定时器：每 5 秒检查轮询是否还活着（分屏挂边时系统可能挂起 Task）
            // 恢复屏幕常亮设置
            UIApplication.shared.isIdleTimerDisabled =
                UserDefaults.standard.bool(forKey: "keepAwake")
            Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                Task { @MainActor in store.ensurePollingAlive() }
            }
        }
        .onChange(of: store.isLoggedIn) { ok in
            if ok { store.startPolling() } else { store.stopPolling() }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                // 回到前台 / 分屏恢复：重启轮询并立即刷新
                Task { await store.resumeFromBackground() }
            case .inactive:
                // 分屏挂边、下拉通知中心等：保持轮询，只补一次刷新
                Task { await store.fetchStatus() }
            case .background:
                // 真正进入后台：停止轮询节省资源
                store.stopPolling()
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

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
    }
}
