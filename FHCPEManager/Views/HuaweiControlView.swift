import SwiftUI

/// 华为控制页
struct HuaweiControlView: View {
    @EnvironmentObject var store: CpeStore

    @State private var mobileData = true
    @State private var ledOn = true
    @State private var timedReboot = false
    @State private var startTime = "03:00"
    @State private var endTime = "04:00"
    @State private var busy = false
    @State private var showReboot = false
    @State private var showFactory = false
    @State private var showTimed = false

    private var s: CpeStatus { store.status }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    statusBanner
                    mobileDataCard
                    quickActions
                    timedRebootCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .scrollContentBackground(.hidden)
            .background(GlassListBackground())
            .navigationTitle("控制")
            .alert("重启设备", isPresented: $showReboot) {
                Button("取消", role: .cancel) { }
                Button("重启", role: .destructive) {
                    Haptic.warning()
                    Task {
                        let ok = await HuaweiAPI.shared.reboot()
                        store.toast(ok ? "重启指令已发送，设备将在约 1 分钟后恢复"
                                       : (HuaweiAPI.shared.lastErrorText.isEmpty ? "重启失败" : HuaweiAPI.shared.lastErrorText),
                                    kind: ok ? .success : .error)
                    }
                }
            } message: {
                Text("重启期间所有终端会断网。")
            }
            .alert("恢复出厂设置", isPresented: $showFactory) {
                Button("取消", role: .cancel) { }
                Button("恢复", role: .destructive) {
                    Haptic.warning()
                    Task {
                        let ok = await HuaweiAPI.shared.factoryReset()
                        store.toast(ok ? "恢复出厂指令已下发" : "操作失败",
                                    kind: ok ? .success : .error)
                    }
                }
            } message: {
                Text("名称、密码、锁频等全部配置都会清空，且无法撤销。")
            }
            .sheet(isPresented: $showTimed) { timedSheet }
            .task { loadState() }
        }
    }

    // MARK: 状态

    private var statusBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(s["connStatus"] == "901" ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(s["carrier"].isEmpty ? "未识别运营商" : s["carrier"])
                    .font(.system(size: 14, weight: .semibold))
                Text(netText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !s["rsrp"].isEmpty {
                Text("\(s["rsrp"]) dBm")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassCard(radius: 16)
    }

    private var netText: String {
        let t = s["netmode"]
        switch t {
        case "3": return "5G"
        case "2": return "4G"
        default:  return t.isEmpty ? "未知网络" : t
        }
    }

    // MARK: 移动数据

    private var mobileDataCard: some View {
        Button {
            Haptic.medium()
            let target = !mobileData
            mobileData = target
            Task {
                busy = true
                let ok = await HuaweiAPI.shared.setMobileData(target)
                busy = false
                if !ok {
                    mobileData = !target
                    store.toast("设置失败", kind: .error)
                } else {
                    store.toast(target ? "移动数据已开启" : "移动数据已关闭", kind: .success)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mobileData ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(mobileData ? Color.blue : Color.secondary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill((mobileData ? Color.blue : Color.secondary).opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("移动数据")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(mobileData ? "已开启，可正常上网" : "已关闭，仅局域网可用")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if busy {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Text(mobileData ? "开" : "关")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(mobileData ? Color.green : Color.secondary.opacity(0.5)))
                }
            }
            .padding(14)
            .glassCard(radius: 18)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    // MARK: 快捷操作

    private var quickActions: some View {
        HStack(spacing: 10) {
            actionCard("重启设备", "power", .red) {
                showReboot = true
            }
            actionCard("恢复出厂", "arrow.counterclockwise", .orange) {
                showFactory = true
            }
        }
    }

    private func actionCard(_ title: String, _ icon: String, _ tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button {
            Haptic.warning()
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .glassCard(radius: 18)
        }
        .buttonStyle(.plain)
    }

    // MARK: 定时重启

    private var timedRebootCard: some View {
        Button {
            Haptic.light()
            showTimed = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.purple)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.purple.opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("定时重启")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(timedReboot ? "\(startTime) – \(endTime)" : "未开启")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(14)
            .glassCard(radius: 18)
        }
        .buttonStyle(.plain)
    }

    private var timedSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("启用定时重启", isOn: $timedReboot)
                }
                Section {
                    HStack {
                        Text("开始时间")
                        Spacer()
                        TextField("03:00", text: $startTime)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    HStack {
                        Text("结束时间")
                        Spacer()
                        TextField("04:00", text: $endTime)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                    }
                } header: {
                    Text("时间窗")
                } footer: {
                    Text("在指定时间窗内自动重启一次。格式 HH:mm，开始时间需早于结束时间。")
                }
            }
            .navigationTitle("定时重启")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showTimed = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            let ok = await HuaweiAPI.shared.setTimedReboot(
                                enable: timedReboot, start: startTime, end: endTime)
                            store.toast(ok ? "定时重启已保存" : "保存失败",
                                        kind: ok ? .success : .error)
                            showTimed = false
                        }
                    }
                }
            }
        }
    }

    private func loadState() {
        // 从当前状态推断移动数据（ConnectionStatus 901 = 已连接）
        let c = store.status["connStatus"]
        if !c.isEmpty {
            mobileData = (c == "901" || c == "902")
        }
    }
}
