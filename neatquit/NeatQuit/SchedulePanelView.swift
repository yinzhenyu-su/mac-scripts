import AppKit
import SwiftUI

/// 两个面板共用的时长输入与校验。
enum DurationInput {
    static let presets = [5, 15, 30, 60, 120]
    static let maximumMinutes = 1440

    static func resolve(selectedMinutes: Int, customText: String) -> Int? {
        guard selectedMinutes == 0 else { return selectedMinutes }
        guard let value = Int(customText.trimmingCharacters(in: .whitespacesAndNewlines)),
              value > 0, value <= maximumMinutes else { return nil }
        return value
    }

    static func initialState(minutes: Int, prefersCustom: Bool) -> (selected: Int, custom: String) {
        if prefersCustom { return (0, "") }
        if presets.contains(minutes) { return (minutes, "") }
        return (0, String(minutes))
    }
}

/// 预设下拉 + 自定义分钟输入，应用面板与磁盘面板共用。
struct DurationSelector: View {
    @Binding var selectedMinutes: Int
    @Binding var customText: String
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .frame(width: 58, alignment: .leading)
            Picker("", selection: $selectedMinutes) {
                ForEach(DurationInput.presets, id: \.self) { minutes in
                    Text("\(minutes)").tag(minutes)
                }
                Text(L10n.schedulePanelCustom).tag(0)
            }
            .labelsHidden()
            .frame(width: 110)
            if selectedMinutes == 0 {
                TextField("", text: $customText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
            }
            Text(L10n.schedulePanelMinutes)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

/// 「添加定时退出」面板。两个入口共用：快路径预填当前应用与 30 分钟，普通入口默认 30 分钟。
struct ScheduleEditorView: View {
    let applications: [NSRunningApplication]
    let initialBundleID: String?
    let initialMinutes: Int
    let onStart: (NSRunningApplication, Int) -> Void
    let onCancel: () -> Void

    @State private var selectedBundleID: String
    @State private var selectedMinutes: Int
    @State private var customText: String

    init(
        applications: [NSRunningApplication],
        initialBundleID: String?,
        initialMinutes: Int,
        prefersCustomDuration: Bool = false,
        onStart: @escaping (NSRunningApplication, Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.applications = applications
        self.initialBundleID = initialBundleID
        self.initialMinutes = initialMinutes
        self.onStart = onStart
        self.onCancel = onCancel
        _selectedBundleID = State(
            initialValue: initialBundleID ?? applications.first?.bundleIdentifier ?? ""
        )
        let initial = DurationInput.initialState(minutes: initialMinutes, prefersCustom: prefersCustomDuration)
        _selectedMinutes = State(initialValue: initial.selected)
        _customText = State(initialValue: initial.custom)
    }

    private var resolvedMinutes: Int? {
        DurationInput.resolve(selectedMinutes: selectedMinutes, customText: customText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.schedulePanelTitle)
                .font(.title3.bold())

            if applications.isEmpty {
                Text(L10n.schedulePanelNoApps)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(L10n.schedulePanelApp)
                        .frame(width: 58, alignment: .leading)
                    Picker("", selection: $selectedBundleID) {
                        ForEach(applications, id: \.bundleIdentifier) { application in
                            Text(application.localizedName ?? application.bundleIdentifier ?? "—")
                                .tag(application.bundleIdentifier ?? "")
                        }
                    }
                    .labelsHidden()
                    Spacer(minLength: 0)
                }

                DurationSelector(
                    selectedMinutes: $selectedMinutes,
                    customText: $customText,
                    label: L10n.schedulePanelDuration
                )

                if selectedMinutes == 0, !customText.isEmpty, resolvedMinutes == nil {
                    Text(L10n.schedulePanelInvalid)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text(L10n.schedulePanelNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Spacer()
                Button(L10n.cancel) { onCancel() }
                Button(L10n.schedulePanelStart) { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(resolvedMinutes == nil || selectedBundleID.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func start() {
        guard let minutes = resolvedMinutes,
              let application = applications.first(where: { $0.bundleIdentifier == selectedBundleID })
        else { return }
        onStart(application, minutes)
    }
}

/// 「添加定时弹出」面板。形状与应用面板一致，只是目标换成磁盘。
struct EjectPanelView: View {
    let disks: [ScheduledDisk]
    let initialDiskID: String?
    let initialMinutes: Int
    let onStart: (ScheduledDisk, Int) -> Void
    let onCancel: () -> Void

    @State private var selectedDiskID: String
    @State private var selectedMinutes: Int
    @State private var customText: String

    init(
        disks: [ScheduledDisk],
        initialDiskID: String?,
        initialMinutes: Int,
        prefersCustomDuration: Bool = false,
        onStart: @escaping (ScheduledDisk, Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.disks = disks
        self.initialDiskID = initialDiskID
        self.initialMinutes = initialMinutes
        self.onStart = onStart
        self.onCancel = onCancel
        _selectedDiskID = State(initialValue: initialDiskID ?? disks.first?.bsdName ?? "")
        let initial = DurationInput.initialState(minutes: initialMinutes, prefersCustom: prefersCustomDuration)
        _selectedMinutes = State(initialValue: initial.selected)
        _customText = State(initialValue: initial.custom)
    }

    private var resolvedMinutes: Int? {
        DurationInput.resolve(selectedMinutes: selectedMinutes, customText: customText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.ejectPanelTitle)
                .font(.title3.bold())

            if disks.isEmpty {
                Text(L10n.ejectPanelNoDisks)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(L10n.ejectPanelDisk)
                        .frame(width: 58, alignment: .leading)
                    Picker("", selection: $selectedDiskID) {
                        ForEach(disks) { disk in
                            Text(disk.displayName).tag(disk.bsdName)
                        }
                    }
                    .labelsHidden()
                    Spacer(minLength: 0)
                }

                DurationSelector(
                    selectedMinutes: $selectedMinutes,
                    customText: $customText,
                    label: L10n.schedulePanelDuration
                )

                if selectedMinutes == 0, !customText.isEmpty, resolvedMinutes == nil {
                    Text(L10n.schedulePanelInvalid)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text(L10n.ejectPanelNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Spacer()
                Button(L10n.cancel) { onCancel() }
                Button(L10n.schedulePanelStart) { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(resolvedMinutes == nil || selectedDiskID.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func start() {
        guard let minutes = resolvedMinutes,
              let disk = disks.first(where: { $0.bsdName == selectedDiskID })
        else { return }
        onStart(disk, minutes)
    }
}

#if DEBUG
#Preview("Add Quit Timer") {
    ScheduleEditorView(
        applications: NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        },
        initialBundleID: nil,
        initialMinutes: 30,
        onStart: { _, _ in },
        onCancel: {}
    )
}
#endif
