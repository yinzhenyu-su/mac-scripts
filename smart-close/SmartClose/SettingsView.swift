import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: RuleStore
    @State private var errorMessage: String?

    private var sortedRules: [AppRule] {
        store.rules.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("不自动退出的 App")
                .font(.title2.bold())
            Text("列表中的 App 在关闭最后一个窗口时，会保留后台或自行管理后台")
                .foregroundStyle(.secondary)

            List(sortedRules) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rule.displayName)
                        Text(rule.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("移除") { store.remove(rule) }
                        .buttonStyle(.borderless)
                }
            }
            .frame(minHeight: 300)

            HStack {
                Button("添加 App…") { chooseApplication() }
                Spacer()
                Text("不在上方列表中的 App 在关闭最后一个标准窗口时会自动退出")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 560, height: 440)
        .alert("无法添加 App", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.message = "选择需要在关闭最后一个窗口后继续运行的 App"
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.addApplication(at: url) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
