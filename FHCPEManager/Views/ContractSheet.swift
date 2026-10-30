import SwiftUI

/// 自定义签约速率输入
struct ContractSheet: View {
    @Binding var down: String
    @Binding var up: String
    let deviceDown: String
    let deviceUp: String

    @Environment(\.dismiss) var dismiss
    @State private var d = ""
    @State private var u = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("签约下行")
                        Spacer()
                        TextField(deviceDown, text: $d)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("Mbps").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("签约上行")
                        Spacer()
                        TextField(deviceUp, text: $u)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("Mbps").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("留空则显示设备实际值（\(deviceDown) / \(deviceUp) Mbps）。仅影响本 App 显示，不修改设备。")
                }

                Section {
                    Button("恢复设备实际值") {
                        d = ""
                        u = ""
                        down = ""
                        up = ""
                        dismiss()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("签约速率")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        down = d.trimmingCharacters(in: .whitespaces)
                        up = u.trimmingCharacters(in: .whitespaces)
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                d = down
                u = up
            }
        }
    }
}
