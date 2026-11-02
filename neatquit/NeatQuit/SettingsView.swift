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
            Text(L10n.settingsTitle)
                .font(.title2.bold())
            Text(L10n.settingsDescription)
                .foregroundStyle(.secondary)

            List(sortedRules) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rule.displayName)
                        Text(rule.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.remove) { store.remove(rule) }
                        .buttonStyle(.borderless)
                }
            }
            .frame(minHeight: 300)

            HStack {
                Button(L10n.addApp) { chooseApplication() }
                Spacer()
                Text(L10n.settingsFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 560, height: 440)
        .alert(L10n.cannotAddApp, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.okay, role: .cancel) { errorMessage = nil }
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
        panel.message = L10n.chooseAppMessage
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.addApplication(at: url) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
