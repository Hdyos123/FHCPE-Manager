import SwiftUI

/// 全局 Tab 路由：首页那四个按钮可以直接跳转到对应 Tab
final class TabRouter: ObservableObject {
    @Published var selection: Int = 0

    enum Tab: Int {
        case home = 0, sms, control, lock, param, settings
    }

    func go(_ t: Tab) { selection = t.rawValue }
}

/// 某功能当前设备不支持时的占位
struct UnsupportedView: View {
    let title: String
    let detail: String

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .padding(.top, 60)

                Text(title)
                    .font(.system(size: 16, weight: .semibold))

                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GlassListBackground())
        .navigationTitle(title)
    }
}

// MARK: - 各 Tab 的厂商分流

struct SmsTab: View {
    @EnvironmentObject var store: CpeStore

    var body: some View {
        if store.isHuawei {
            HuaweiSmsView()
        } else if store.isFiberHome {
            SmsView()
        } else {
            UnsupportedView(title: "短信",
                            detail: "当前设备（OPPO）暂未开放短信接口。\n华为和烽火设备支持收发短信。")
        }
    }
}

struct ControlTab: View {
    @EnvironmentObject var store: CpeStore

    var body: some View {
        if store.isHuawei {
            HuaweiControlView()
        } else {
            ControlView()
        }
    }
}

struct LockTab: View {
    @EnvironmentObject var store: CpeStore

    var body: some View {
        if store.isHuawei {
            HuaweiLockView()
        } else if store.isFiberHome {
            LockBandView()
        } else {
            UnsupportedView(title: "锁频",
                            detail: "当前设备（OPPO）暂未开放锁频接口。\n华为和烽火设备支持锁频。")
        }
    }
}

struct ParamTab: View {
    @EnvironmentObject var store: CpeStore

    var body: some View {
        ParamView()
    }
}
