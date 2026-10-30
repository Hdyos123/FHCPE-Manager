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

            // 全局提示
            if let t = store.toastText {
                VStack {
                    Spacer()
                    Text(t)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.78)))
                        .padding(.bottom, 100)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.2), value: store.toastText)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.isLoggedIn)
        .onAppear {
            Task { await store.tryAutoLogin() }
        }
        .onChange(of: store.isLoggedIn) { ok in
            if ok { store.startPolling() } else { store.stopPolling() }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                // 回到前台：恢复轮询并立即刷新
                Task { await store.resumeFromBackground() }
            case .background:
                // 进入后台：停止轮询节省资源
                store.stopPolling()
            default:
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
