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
        }
        .animation(.easeInOut(duration: 0.25), value: store.isLoggedIn)
        .onAppear {
            Task { await store.tryAutoLogin() }
        }
        .onChange(of: store.isLoggedIn) { ok in
            if ok { store.startPolling() } else { store.stopPolling() }
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
            // 底栏只保留 首页 / 设置
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
            MoreView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
    }
}

/// 「更多」：承载控制 / 锁频 / 参数 / 短信
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink { ControlView() } label: {
                    Label("控制", systemImage: "slider.horizontal.3")
                }
                NavigationLink { LockBandView() } label: {
                    Label("锁频", systemImage: "lock.fill")
                }
                NavigationLink { ParamView() } label: {
                    Label("参数", systemImage: "doc.text")
                }
                NavigationLink { SmsView() } label: {
                    Label("短信", systemImage: "message.fill")
                }
                NavigationLink { SettingsView() } label: {
                    Label("设置", systemImage: "gearshape.fill")
                }
            }
            .navigationTitle("更多")
        }
    }
}

