import SwiftUI

/// 华为短信（列表 / 发送 / 删除 / 验证码提取）
struct HuaweiSmsView: View {
    @EnvironmentObject var store: CpeStore

    @State private var items: [HuaweiAPI.SmsItem] = []
    @State private var loading = false
    @State private var showCompose = false
    @State private var composeTo = ""
    @State private var composeText = ""
    @State private var sending = false
    @State private var pendingDelete: HuaweiAPI.SmsItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if loading && items.isEmpty {
                        ProgressView().padding(.top, 60)
                    } else if items.isEmpty {
                        emptyView
                    } else {
                        ForEach(items) { m in
                            row(m)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .scrollContentBackground(.hidden)
            .background(GlassListBackground())
            .navigationTitle("短信")
            .refreshable { await reload() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptic.light()
                        composeTo = ""
                        composeText = ""
                        showCompose = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showCompose) {
                composeSheet
                    .presentationDetents([.medium, .large])
            }
            .alert("删除短信", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )) {
                Button("取消", role: .cancel) { pendingDelete = nil }
                Button("删除", role: .destructive) {
                    guard let m = pendingDelete else { return }
                    pendingDelete = nil
                    Task {
                        let ok = await HuaweiAPI.shared.deleteSms(indices: [m.index])
                        store.toast(ok ? "已删除" : "删除失败", kind: ok ? .success : .error)
                        if ok { await reload() }
                    }
                }
            } message: {
                Text("短信将从设备与 SIM 卡上永久删除，无法撤销。")
            }
            .task { await reload() }
        }
    }

    // MARK: 行

    private func row(_ m: HuaweiAPI.SmsItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: m.outgoing ? "arrow.up.right" : "arrow.down.left")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(m.outgoing ? Color.orange : Color.blue)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill((m.outgoing ? Color.orange : Color.blue).opacity(0.12)))

                Text(m.phone.isEmpty ? "未知号码" : m.phone)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Text(shortDate(m.date))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Text(m.content)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 验证码
            if let code = verificationCode(m.content) {
                Button {
                    Haptic.success()
                    UIPasteboard.general.string = code
                    store.toast("已复制验证码 \(code)", kind: .success)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                        Text("复制验证码 \(code)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.blue.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .glassCard(radius: 16)
        .contextMenu {
            Button {
                UIPasteboard.general.string = m.content
                store.toast("已复制内容", kind: .success)
            } label: { Label("复制内容", systemImage: "doc.on.doc") }

            Button(role: .destructive) {
                pendingDelete = m
            } label: { Label("删除", systemImage: "trash") }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "message")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("暂无短信")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("下拉可重新读取")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(.top, 70)
    }

    // MARK: 发送

    private var composeSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("号码，多个用逗号分隔", text: $composeTo)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                } header: { Text("收件人") }

                Section {
                    TextEditor(text: $composeText)
                        .frame(minHeight: 110)
                        .font(.system(size: 14))
                } header: { Text("内容") }
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
                        if sending { ProgressView().scaleEffect(0.8) }
                        else { Text("发送") }
                    }
                    .disabled(sending || composeTo.isEmpty || composeText.isEmpty)
                }
            }
        }
    }

    private func send() async {
        sending = true
        let nums = composeTo
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == ";" || $0 == " " })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let ok = await HuaweiAPI.shared.sendSms(to: nums, text: composeText)
        sending = false
        if ok {
            store.toast("短信已发送", kind: .success)
            showCompose = false
            await reload()
        } else {
            store.toast(HuaweiAPI.shared.lastErrorText.isEmpty
                        ? "发送失败" : HuaweiAPI.shared.lastErrorText, kind: .error)
        }
    }

    private func reload() async {
        loading = true
        let list = await HuaweiAPI.shared.fetchSms()
        items = list
        loading = false
    }

    // MARK: 工具

    /// 从短信里提取 4-8 位验证码
    private func verificationCode(_ s: String) -> String? {
        let pattern = "(?<![0-9])([0-9]{4,8})(?![0-9])"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        // 需要上下文里有「验证码 / 校验码 / code」字样才认为是验证码
        let lower = s.lowercased()
        guard lower.contains("验证码") || lower.contains("校验码")
                || lower.contains("动态码") || lower.contains("code") else { return nil }
        guard let m = re.firstMatch(in: s, range: range),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    private func shortDate(_ s: String) -> String {
        // 2024-01-02 12:34:56 → 01-02 12:34
        if s.count >= 16 {
            let idx = s.index(s.startIndex, offsetBy: 5)
            let idx2 = s.index(s.startIndex, offsetBy: 16)
            return String(s[idx..<idx2])
        }
        return s
    }
}
