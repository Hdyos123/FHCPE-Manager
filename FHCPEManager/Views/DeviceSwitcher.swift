import SwiftUI

/// 首页顶栏弹出的设备切换面板
struct DeviceSwitcher: View {
    @EnvironmentObject var store: CpeStore
    @Environment(\.dismiss) var dismiss

    @State private var profiles: [CpeProfile] = []
    @State private var switching: UUID?
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(profiles) { p in
                        Button {
                            switchTo(p)
                        } label: {
                            row(p)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                ProfileStore.delete(p)
                                profiles = ProfileStore.loadAll()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }

                    if profiles.isEmpty {
                        Text("还没有保存的设备")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("已保存的设备")
                } footer: {
                    Text("点击切换。地址与密码分别保存，凭据只存在本机钥匙串。")
                }

                Section {
                    Button {
                        showAdd = true
                    } label: {
                        Label("添加新设备", systemImage: "plus.circle.fill")
                            .font(.system(size: 15, weight: .medium))
                    }
                }
            }
            .navigationTitle("切换设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddDeviceSheet { p in
                    ProfileStore.upsert(p)
                    profiles = ProfileStore.loadAll()
                }
                .presentationDetents([.medium])
            }
            .onAppear {
                profiles = ProfileStore.loadAll()
            }
        }
    }

    private func row(_ p: CpeProfile) -> some View {
        let isActive = store.activeProfile?.id == p.id
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.blue.opacity(isActive ? 0.18 : 0.10))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: p.vendor.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.blue)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(p.displayTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    if isActive {
                        Text("当前")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.blue.opacity(0.14)))
                    }
                }
                Text(p.displaySubtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if switching == p.id {
                ProgressView().scaleEffect(0.8)
            } else if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private func switchTo(_ p: CpeProfile) {
        guard store.activeProfile?.id != p.id else { dismiss(); return }
        Haptic.medium()
        switching = p.id

        Task {
            store.stopPolling()
            let ok = await store.login(profile: p)
            switching = nil
            if ok {
                ProfileStore.activeID = p.id
                store.startPolling()
                store.toast("已切换到 " + p.displayTitle, kind: .success)
                dismiss()
            } else {
                store.toast(store.errorText ?? "切换失败", kind: .error)
            }
        }
    }
}

// MARK: - 添加设备

struct AddDeviceSheet: View {
    let onSave: (CpeProfile) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var vendor: CpeVendor = .fiberhome
    @State private var name = ""
    @State private var host = CpeVendor.fiberhome.defaultHost
    @State private var user = CpeVendor.fiberhome.defaultUser
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("厂商") {
                    Picker("厂商", selection: $vendor) {
                        ForEach(CpeVendor.allCases, id: \.self) { v in
                            Text(v.displayName).tag(v)
                        }
                    }
                    .onChange(of: vendor) { v in
                        host = v.defaultHost
                        user = v.defaultUser
                    }
                }

                Section("连接信息") {
                    TextField("备注名称", text: $name)
                    TextField("管理地址", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("账号", text: $user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                }
            }
            .navigationTitle("添加设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var p = CpeProfile.make(vendor: vendor)
                        p.name = name.isEmpty ? vendor.displayName : name
                        p.host = host
                        p.user = user
                        p.password = password
                        onSave(p)
                        dismiss()
                    }
                    .disabled(host.isEmpty || user.isEmpty || password.isEmpty)
                }
            }
        }
    }
}
