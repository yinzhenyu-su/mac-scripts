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

/// 「磁盘弹出」面板：磁盘选择、立即弹出、触发方式、时长与当前规则都集中在这里。
struct EjectPanelView: View {
    let disks: [ScheduledDisk]
    let initialDiskID: String?
    let initialMode: ScheduleMode
    let initialMinutes: Int
    let prefersCustomDuration: Bool
    /// 直接观察规则存储，取消或触发后「当前规则」行能立即刷新。
    @ObservedObject var scheduledActions: ScheduledActionStore
    /// 以整盘 BSD 名为键的活动计数可用性。
    let idleSupport: [String: Bool]
    let onStart: (ScheduledDisk, ScheduleMode, Int) -> Void
    let onEjectNow: (ScheduledDisk) -> Void
    let onCancelRule: (ScheduledAction) -> Void
    let onCancel: () -> Void

    @State private var selectedDiskID: String
    @State private var selectedMode: ScheduleMode
    @State private var selectedMinutes: Int
    @State private var customText: String

    init(
        disks: [ScheduledDisk],
        initialDiskID: String?,
        initialMode: ScheduleMode,
        initialMinutes: Int,
        prefersCustomDuration: Bool = false,
        scheduledActions: ScheduledActionStore,
        idleSupport: [String: Bool] = [:],
        onStart: @escaping (ScheduledDisk, ScheduleMode, Int) -> Void,
        onEjectNow: @escaping (ScheduledDisk) -> Void,
        onCancelRule: @escaping (ScheduledAction) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.disks = disks
        self.initialDiskID = initialDiskID
        self.initialMode = initialMode
        self.initialMinutes = initialMinutes
        self.prefersCustomDuration = prefersCustomDuration
        self.scheduledActions = scheduledActions
        self.idleSupport = idleSupport
        self.onStart = onStart
        self.onEjectNow = onEjectNow
        self.onCancelRule = onCancelRule
        self.onCancel = onCancel
        _selectedDiskID = State(initialValue: initialDiskID ?? disks.first?.bsdName ?? "")
        _selectedMode = State(initialValue: initialMode)
        let initial = DurationInput.initialState(minutes: initialMinutes, prefersCustom: prefersCustomDuration)
        _selectedMinutes = State(initialValue: initial.selected)
        _customText = State(initialValue: initial.custom)
    }

    private var selectedDisk: ScheduledDisk? {
        disks.first { $0.bsdName == selectedDiskID }
    }

    private var rules: [String: ScheduledAction] {
        Dictionary(
            uniqueKeysWithValues: scheduledActions.actions
                .filter { $0.target.kind == .disk }
                .map { ($0.target.identifier, $0) }
        )
    }

    private var currentRule: ScheduledAction? {
        guard let selectedDisk else { return nil }
        return rules[selectedDisk.mainVolumePath]
    }

    private var idleAvailable: Bool {
        guard let selectedDisk else { return false }
        return idleSupport[selectedDisk.bsdName] ?? false
    }

    private var effectiveMode: ScheduleMode {
        selectedMode == .idle && !idleAvailable ? .timed : selectedMode
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
                    Button(L10n.ejectNow) {
                        if let selectedDisk { onEjectNow(selectedDisk) }
                    }
                    .disabled(selectedDisk == nil)
                    Spacer(minLength: 0)
                }

                HStack(alignment: .top, spacing: 10) {
                    Text(L10n.ejectPanelMode)
                        .frame(width: 58, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        modeRow(.timed, title: L10n.ejectPanelModeTimed)
                        modeRow(.idle, title: L10n.ejectPanelModeIdle)
                        if !idleAvailable {
                            Text(L10n.ejectPanelIdleUnsupported)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                DurationSelector(
                    selectedMinutes: $selectedMinutes,
                    customText: $customText,
                    label: effectiveMode == .idle
                        ? L10n.ejectPanelIdleDuration
                        : L10n.schedulePanelDuration
                )

                if selectedMinutes == 0, !customText.isEmpty, resolvedMinutes == nil {
                    Text(L10n.schedulePanelInvalid)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let currentRule {
                    currentRuleRow(currentRule)
                }

                Text(
                    effectiveMode == .idle
                        ? L10n.ejectPanelIdleNote(minutes: resolvedMinutes ?? 0)
                        : L10n.ejectPanelNote
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Spacer()
                Button(L10n.close) { onCancel() }
                Button(effectiveMode == .idle ? L10n.ejectPanelStartIdle : L10n.ejectPanelStartTimed) {
                    start()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(resolvedMinutes == nil || selectedDiskID.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onChange(of: selectedDiskID) { _ in
            syncToSelectedDisk()
        }
    }

    private func modeRow(_ mode: ScheduleMode, title: String) -> some View {
        let disabled = mode == .idle && !idleAvailable
        return Button {
            selectedMode = mode
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selectedMode == mode ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(disabled ? Color.secondary : Color.accentColor)
                Text(title)
                    .foregroundStyle(disabled ? .secondary : .primary)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func currentRuleRow(_ rule: ScheduledAction) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(L10n.ejectPanelCurrentRule)
                .frame(width: 58, alignment: .leading)
            Text(currentRuleTitle(rule))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(L10n.ejectPanelCancelRule) { onCancelRule(rule) }
        }
    }

    private func currentRuleTitle(_ rule: ScheduledAction) -> String {
        switch rule.state {
        case .refused:
            return L10n.diskRefusedTitle(rule.displayName)
        case .firing:
            return L10n.diskFiringTitle(rule.displayName)
        case .armed:
            let remaining = ScheduleDecision.remainingText(fireAt: rule.fireAt, now: Date())
            if let minutes = rule.idleMinutes {
                return L10n.ejectPanelCurrentIdle(minutes: minutes, remaining: remaining)
            }
            return L10n.ejectPanelCurrentTimed(remaining: remaining)
        }
    }

    /// 切换磁盘时同步该磁盘已有的规则；没有规则则保留当前方式与时长。
    private func syncToSelectedDisk() {
        guard let selectedDisk else { return }
        if let rule = rules[selectedDisk.mainVolumePath] {
            selectedMode = rule.mode
            let minutes: Int
            if let idle = rule.idleMinutes {
                minutes = idle
            } else {
                minutes = max(1, Int((rule.fireAt.timeIntervalSinceNow / 60).rounded()))
            }
            let state = DurationInput.initialState(
                minutes: minutes,
                prefersCustom: !DurationInput.presets.contains(minutes)
            )
            selectedMinutes = state.selected
            customText = state.custom
        }
        if selectedMode == .idle, !(idleSupport[selectedDisk.bsdName] ?? false) {
            selectedMode = .timed
        }
    }

    private func start() {
        guard let minutes = resolvedMinutes, let disk = selectedDisk else { return }
        onStart(disk, effectiveMode, minutes)
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
