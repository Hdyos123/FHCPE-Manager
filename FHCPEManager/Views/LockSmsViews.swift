import SwiftUI

// MARK: - 短信

struct SmsView: View {
    @EnvironmentObject var store: CpeStore
    @State private var list: [CpeSms] = []
    @State private var loading = false
    @State private var showCompose = false
    @State private var composeTo = ""
    @State private var composeText = ""

    var body: some View {
        NavigationStack {
            WideAdapter(maxWidth: 560) {
            Group {
                if loading && list.isEmpty {
                    ProgressView("读取中…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if list.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "message")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary.opacity(0.6))
                        Text("暂无短信").font(.system(size: 17, weight: .semibold))
                        Text("收件箱是空的")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(list) { m in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(m.sender.isEmpty ? "未知号码" : m.sender)
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Text(m.time)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Text(m.content)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                        .padding(.vertical, 3)
                    }
                    .refreshable { await load() }
                }
            }
            .background(AppBackground())
            .glassListStyle()
            .navigationTitle("短信")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCompose = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showCompose) {
                composeSheet.presentationDetents([.medium])
            }
            .task { await load() }
        }
    }

    private var composeSheet: some View {
        NavigationStack {
            Form {
                Section("接收号码") {
                    TextField("手机号", text: $composeTo)
                        .keyboardType(.phonePad)
                }
                Section("内容") {
                    TextField("短信内容", text: $composeText, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Button {
                        sendSms()
                    } label: {
                        Text("发送").frame(maxWidth: .infinity)
                    }
                    .disabled(composeTo.isEmpty || composeText.isEmpty)
                }
            }
            .navigationTitle("发送短信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showCompose = false }
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        list = await store.fetchSms()
        if list.isEmpty { store.toast("暂无短信", kind: .info) }
    }

    private func sendSms() {
        Task {
            _ = await store.sendSms(to: composeTo, text: composeText)
            store.toast("短信已发送", kind: .success)
            composeTo = ""
            composeText = ""
            showCompose = false
        }
    }
}
