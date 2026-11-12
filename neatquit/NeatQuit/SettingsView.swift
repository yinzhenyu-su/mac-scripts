import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: RuleStore
    @State private var errorMessage: String?
    @State private var searchText = ""

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sortedRules: [AppRule] {
        store.activeRules.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var filteredRules: [AppRule] {
        guard !trimmedSearchText.isEmpty else { return sortedRules }
        return sortedRules.filter { $0.matches(searchQuery: trimmedSearchText) }
    }

    private var modeBinding: Binding<RuleMode> {
        Binding(
            get: { store.mode },
            set: { newMode in
                searchText = ""
                store.setMode(newMode)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.rulesWindow)
                .font(.title2.bold())
            Text(L10n.settingsDescription)
                .foregroundStyle(.secondary)

            Picker(L10n.settingsModeLabel, selection: modeBinding) {
                Text(L10n.settingsModeExclude).tag(RuleMode.allExceptListed)
                Text(L10n.settingsModeOnly).tag(RuleMode.onlyListed)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .padding(.bottom, 2)

            searchField

            List(filteredRules) { rule in
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
            .overlay {
                if filteredRules.isEmpty {
                    Text(trimmedSearchText.isEmpty
                        ? L10n.settingsEmpty(mode: store.mode)
                        : L10n.settingsNoResults)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Button(L10n.addApp) { chooseApplication() }
                Spacer()
                Text(L10n.settingsFooter(mode: store.mode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 560)
        .alert(L10n.cannotAddApp, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.okay, role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(L10n.settingsSearchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel(L10n.settingsSearchPlaceholder)
                .onExitCommand { searchText = "" }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.settingsClearSearch)
                .accessibilityLabel(L10n.settingsClearSearch)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.message = L10n.chooseAppMessage(mode: store.mode)
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.addApplication(at: url) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

#if DEBUG
#Preview("Exception Apps") {
    SettingsView(store: RuleStore())
}
#endif

struct RuleGuideView: View {
    @ObservedObject var store: RuleStore
    let finish: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("onboarding.title").font(.title2.bold())
            Text(store.mode == .allExceptListed ? "onboarding.exclude" : "onboarding.only")
            List(store.activeRules.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }) { rule in
                VStack(alignment: .leading) {
                    Text(rule.displayName)
                    Text(rule.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("onboarding.permission").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("onboarding.later") { finish(false) }
                Spacer()
                Button("onboarding.adjust") { finish(true) }
                Button("onboarding.confirm") { finish(false) }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 560, height: 500)
    }
}
