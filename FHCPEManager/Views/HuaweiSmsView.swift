import SwiftUI

/// 华为短信 —— 照 CPE Ultra 布局
/// 顶部四个统计卡 / 发送入口 / 短信列表
struct HuaweiSmsView: View {
    @EnvironmentObject var store: CpeStore

    @State private var items: [HuaweiAPI.SmsItem] = []
    @State private var loading = false
    @State private var showCompose = false
    @State private var composeTo = ""
    @State private var composeText = ""
    @State private var sending = false
    @State private var counts = (inbox: 0, outbox: 0, unread: 0)
    @State private var boxFilter = 1          // 1 收件箱 2 已发
    @State private var selectMode = false
    @State private var selected = Set<String>()
    @State private var detail: HuaweiAPI.SmsItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    statRow
                    sendEntry
                    listCard
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 96)
            }
            .background(GlassListBackground())
            .navigationBarHidden(true)
            .refreshable { await reload() }
            .task { await reload() }
            .sheet(isPresented: $showCompose) {
                composeSheet
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $detail) { m in
                detailSheet(m)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: 统计卡

    private var statRow: some View {
        HStack(spacing: 8) {
            statBox("收件箱", "\(counts.inbox)", "tray.full.fill", .blue)
            statBox("发件箱", "\(counts.outbox)", "paperplane.fill", .green)
            statBox("未读", "\(counts.unread)", "envelope.badge.fill", .orange)
            statBox("剩余容量", "\(max(0, 530 - counts.inbox))", "gauge.medium", .purple)
        }
        .padding(10)
        .glassCard(radius: 22)
    }

    private func statBox(_ title: String, _ value: String,
                         _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(color)
                )
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: 发送入口

    private var sendEntry: some View {
        Button {
            Haptic.light()
            composeTo = ""
            composeText = ""
            showCompose = true
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(0.14))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15))
                            .foregroundStyle(.green)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("发送短信")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("支持一次发给多个号码")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(12)
            .glassCard(radius: 18)
        }
        .buttonStyle(.plain)
    }

    // MARK: 列表

    private var listCard: some View {
        VStack(spacing: 10) {
            // 标题行
            HStack(spacing: 8) {
                Text("短信列表")
                    .font(.system(size: 15, weight: .bold))
                Text("\(items.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                Spacer()
                Button {
                    Haptic.light()
                    boxFilter = boxFilter == 1 ? 2 : 1
                    Task { await reload() }
                } label: {
                    HStack(spacing: 3) {
                        Text(boxFilter == 1 ? "收件箱" : "已发送")
                            .font(.system(size: 11.5))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color.blue.opacity(0.10)))
                }
                .buttonStyle(.plain)

                Button {
                    Haptic.light()
                    selectMode.toggle()
                    if !selectMode { selected.removeAll() }
                } label: {
                    Text(selectMode ? "取消" : "选择")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Color.blue.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }

            // 未读 + 全部已读
            HStack {
                Text("\(counts.unread) 条未读")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Haptic.light()
                    Task {
                        _ = await HuaweiAPI.shared.markSmsRead(
                            indices: items.enumerated().map { String($0.offset) })
                        await reload()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.open")
                            .font(.system(size: 10))
                        Text("全部已读")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color.blue.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }

            if loading && items.isEmpty {
                ProgressView().padding(.vertical, 40)
            } else if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "envelope")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("暂无短信")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 36)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, m in
                    Button {
                        Haptic.light()
                        if selectMode {
                            if selected.contains(m.index) { selected.remove(m.index) }
                            else { selected.insert(m.index) }
                        } else {
                            detail = m
                        }
                    } label: {
                        smsRow(m, idx: idx)
                    }
                    .buttonStyle(.plain)
                    if idx < items.count - 1 {
                        Divider().opacity(0.15)
                    }
                }
            }
        }
        .padding(14)
        .glassCard(radius: 22)
    }

    private func smsRow(_ m: HuaweiAPI.SmsItem, idx: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(m.read ? Color.primary.opacity(0.06) : Color.blue.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: m.read ? "envelope" : "envelope.badge.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(m.read ? Color.secondary : Color.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(m.phone)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if !m.read {
                        Circle().fill(Color.blue).frame(width: 5, height: 5)
                    }
                    Spacer()
                    Text(m.date)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Text(m.content)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            if selectMode {
                Image(systemName: selected.contains(m.index) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected.contains(m.index) ? Color.blue : Color.secondary.opacity(0.4))
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: 详情

    private func detailSheet(_ m: HuaweiAPI.SmsItem) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.phone)
                                .font(.system(size: 17, weight: .bold))
                            Text(m.date)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("设备")
                            .font(.system(size: 10))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple.opacity(0.14)))
                    }

                    // 提取链接
                    if let link = extractURL(m.content) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("链接")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                                Text(link)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.blue)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                Haptic.light()
                                UIPasteboard.general.string = link
                                store.toast("已复制", kind: .success)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "doc.on.doc").font(.system(size: 10))
                                    Text("复制").font(.system(size: 11))
                                }
                                .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.blue.opacity(0.08))
                        )
                    }

                    Text(m.content)
                        .font(.system(size: 13))
                        .textSelection(.enabled)

                    HStack(spacing: 10) {
                        actionBtn("复制全文", "doc.on.doc", .blue) {
                            UIPasteboard.general.string = m.content
                            store.toast("已复制", kind: .success)
                        }
                        actionBtn("回复", "arrowshape.turn.up.left", .green) {
                            composeTo = m.phone
                            composeText = ""
                            detail = nil
                            showCompose = true
                        }
                        actionBtn("删除", "trash", .red) {
                            Task {
                                let ok = await HuaweiAPI.shared.deleteSms(indices: [m.index])
                                store.toast(ok ? "已删除" : "删除失败",
                                            kind: ok ? .success : .error)
                                detail = nil
                                await reload()
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("短信详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { detail = nil }
                }
            }
        }
    }

    private func actionBtn(_ title: String, _ icon: String, _ color: Color,
                           action: @escaping () -> Void) -> some View {
        Button {
            Haptic.light()
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(.system(size: 12))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(color.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    private func extractURL(_ s: String) -> String? {
        guard let r = s.range(of: "https?://[^\\s，。]+", options: .regularExpression) else { return nil }
        return String(s[r])
    }

    // MARK: 发送

    private var composeSheet: some View {
        NavigationStack {
            Form {
                Section("收件人") {
                    TextField("多个号码用分号或逗号分隔", text: $composeTo, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section("内容") {
                    TextField("短信内容", text: $composeText, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle("发送短信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showCompose = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await send() }
                    } label: {
                        if sending { ProgressView() } else { Text("发送") }
                    }
                    .disabled(composeTo.isEmpty || composeText.isEmpty || sending)
                }
            }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        let nums = composeTo.components(separatedBy: CharacterSet(charactersIn: ";,，；"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let ok = await HuaweiAPI.shared.sendSms(to: nums, text: composeText)
        if ok {
            store.toast("已发送", kind: .success)
            showCompose = false
            await reload()
        } else {
            store.toast("发送失败", kind: .error)
        }
    }

    // MARK: 加载

    private func reload() async {
        loading = true
        defer { loading = false }
        counts = await HuaweiAPI.shared.fetchSmsCount()
        items = await HuaweiAPI.shared.fetchSms(page: 1, count: 50)
    }
}
