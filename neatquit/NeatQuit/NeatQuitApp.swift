import AppKit
import ApplicationServices
import ServiceManagement
import Sparkle
import SwiftUI

@main
struct NeatQuitMain {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = NeatQuitAppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}

@MainActor
final class NeatQuitAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = CloseMonitor()
    private let store = RuleStore()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var settingsHostingView: NSHostingView<SettingsView>?
    private var onboardingWindow: NSWindow?
    private var onboardingCloseObserver: NSObjectProtocol?
    private var aboutWindow: NSWindow?
    private var licenseWindow: NSWindow?
    private let license = LicenseManager.shared
    private var lastActiveApplication: NSRunningApplication?
    private var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
    private var keyboardEnabled = UserDefaults.standard.bool(forKey: "keyboardEnabled")
    private var accessibilityWasTrusted = AXIsProcessTrusted()
    private var inputMonitoringWasGranted = CGPreflightListenEventAccess()
    private var authorizationTimer: Timer?
    private var restartInProgress = false
    private let scheduledActions = ScheduledActionStore()
    private let diskActivity = DiskActivityMonitor()
    private lazy var scheduler = ScheduledActionScheduler(
        store: scheduledActions,
        isAvailable: { [weak self] action in self?.isTargetAvailable(action) ?? false },
        isStillPresent: { [weak self] action in self?.isTargetStillPresent(action) ?? false },
        perform: { [weak self] action, completion in self?.perform(action, completion: completion) },
        isActive: { [weak self] action in self?.isDiskActive(action) ?? true },
        beginPowerAssertion: { PowerAssertion.begin(reason: "定时任务 \($0)") },
        endPowerAssertion: { PowerAssertion.end($0) }
    )
    private var wakeObserver: NSObjectProtocol?
    private lazy var baseMenuBarIcon: NSImage? = {
        let image = NSImage(named: "MenuBarIcon")
        image?.isTemplate = true
        image?.size = NSSize(width: 24, height: 24)
        return image
    }()
    private lazy var badgedMenuBarIcon: NSImage? = {
        guard let base = baseMenuBarIcon else { return nil }
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.isTemplate = true
        image.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size))
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 16.5, y: 1.5, width: 6, height: 6)).fill()
        image.unlockFocus()
        return image
    }()
    private var scheduleWindow: NSWindow?
    private var ejectWindow: NSWindow?
    private var menuCountdownTimer: Timer?
    private var menuIsOpen = false
    private var scheduleEntryItem: NSMenuItem?
    private var scheduleRows: [ScheduleRow] = []
    private var ejectEntryItem: NSMenuItem?

    private struct ScheduleRow {
        let id: UUID
        let name: String
        let kind: ScheduleTarget.Kind
        let item: NSMenuItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installEditMenu()
        monitor.updatePolicy(store.policy)
        monitor.setKeyboardEnabled(license.isEntitled && keyboardEnabled)
        store.onChange = { [weak self] policy in
            guard let self else { return }
            self.monitor.updatePolicy(policy)
            self.sizeSettingsWindow()
        }
        license.onChange = { [weak self] _ in self?.applyLicenseState() }
        scheduledActions.onChange = { [weak self] _ in
            guard let self else { return }
            self.updateStatusItemBadge()
            if self.menuIsOpen {
                self.updateScheduleTitles()
            } else {
                self.refreshMenu()
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemBadge()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        if enabled { _ = monitor.start() }
        // 触发调度器初始化，让闲置规则在启动时把起点重置为当前时刻。
        _ = scheduler
        refreshMenu()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduler.resetIdleStarts(now: Date())
            }
        }

        authorizationTimer = Timer.scheduledTimer(
            // 2 秒足够及时发现授权变化，同时减少空闲唤醒。
            // 定时退出的到期判定也搭这趟车，不额外引入常驻定时器。
            timeInterval: 2,
            target: self,
            selector: #selector(periodicTick),
            userInfo: nil,
            repeats: true
        )

        Task { await license.validateOnLaunch() }
        if store.needsOnboarding {
            DispatchQueue.main.async { [weak self] in self?.showRuleGuideWhenReady() }
        }
    }

    /// 菜单栏应用默认没有主菜单，文本输入框收不到 Cmd+C/V/A。
    /// 安装一个隐藏的 Edit 菜单，让标准编辑快捷键沿响应链生效。
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editRoot = NSMenuItem(title: L10n.menuEdit, action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: L10n.menuEdit)
        editRoot.submenu = editMenu

        editMenu.addItem(withTitle: L10n.menuUndo, action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: L10n.menuRedo, action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.menuCut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.menuCopy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.menuPaste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.menuSelectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        mainMenu.addItem(editRoot)
        NSApp.mainMenu = mainMenu
    }

    @objc private func periodicTick() {
        if enabled { scheduler.tick() }
        checkAccessibilityAuthorization()
    }

    @objc private func checkAccessibilityAuthorization() {
        // 只有开启 ⌘W 时才需要输入监控状态；关闭时跳过，减少无意义的 TCC 查询。
        if keyboardEnabled {
            let inputMonitoringGranted = CGPreflightListenEventAccess()
            if inputMonitoringGranted != inputMonitoringWasGranted {
                inputMonitoringWasGranted = inputMonitoringGranted
                if inputMonitoringGranted { monitor.retryKeyboard() }
                refreshMenu()
            }
        }

        let trusted = AXIsProcessTrusted()
        guard trusted != accessibilityWasTrusted else { return }
        accessibilityWasTrusted = trusted

        if trusted {
            restartAfterPermissionGrant()
        } else {
            monitor.stop()
            refreshMenu()
        }
    }

    private func restartAfterPermissionGrant() {
        guard !restartInProgress else { return }
        restartInProgress = true

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] launchedApp, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let launchedApp,
                   launchedApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    self.authorizationTimer?.invalidate()
                    self.monitor.stop()
                    NSApp.terminate(nil)
                } else {
                    self.restartInProgress = false
                    if self.enabled { _ = self.monitor.start() }
                    self.refreshMenu()
                }
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        lastActiveApplication = frontmost == NSRunningApplication.current ? nil : frontmost
        if enabled && !monitor.isRunning { _ = monitor.start() }
        if enabled && keyboardEnabled { monitor.retryKeyboard() }
        menuIsOpen = true
        refreshMenu()
        startMenuCountdown()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        stopMenuCountdown()
    }

    // MARK: - 菜单组装
    // 六段：状态 / 全局配置 / 辅助退出 / 定时退出应用 / 定时弹出硬盘 / 应用命令。

    private func refreshMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        menu.autoenablesItems = false
        scheduleEntryItem = nil
        scheduleRows.removeAll(keepingCapacity: true)
        ejectEntryItem = nil

        if addStatusSection(to: menu) {
            menu.addItem(.separator())
        }
        addGlobalSection(to: menu)
        menu.addItem(.separator())
        addAssistiveSection(to: menu)
        menu.addItem(.separator())
        addAppScheduleSection(to: menu)
        menu.addItem(.separator())
        if addDiskScheduleSection(to: menu) {
            menu.addItem(.separator())
        }
        addApplicationSection(to: menu)
    }

    /// 状态段只在有信息需要提示时出现；一切正常时不再用一行灰字复述开关状态。
    @discardableResult
    private func addStatusSection(to menu: NSMenu) -> Bool {
        let accessibilityGranted = AXIsProcessTrusted()
        var hasContent = false

        let refused = scheduledActions.actions.filter { $0.state == .refused }
        if !refused.isEmpty {
            let item = NSMenuItem(
                title: L10n.statusIncomplete(count: refused.count, detail: refusedDetail(refused)),
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
            hasContent = true
        }

        let status = L10n.status(
            for: accessibilityGranted,
            enabled: enabled,
            monitorRunning: monitor.isRunning)
        if status != L10n.enabled {
            let statusItem = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
            hasContent = true
        }

        if case .trial = license.tier {
            let licenseStatus = NSMenuItem(title: licenseSummaryTitle, action: nil, keyEquivalent: "")
            licenseStatus.isEnabled = false
            menu.addItem(licenseStatus)
            hasContent = true
        }

        if !accessibilityGranted {
            let permission = NSMenuItem(title: L10n.grantAccessibility, action: #selector(requestAccessibility), keyEquivalent: "")
            permission.target = self
            menu.addItem(permission)
            hasContent = true
        }

        if enabled && keyboardEnabled && accessibilityGranted && !monitor.isKeyboardRunning {
            let keyboardStatus = NSMenuItem(
                title: CGPreflightListenEventAccess() ? L10n.keyboardFailed : L10n.keyboardPermissionRequired,
                action: nil,
                keyEquivalent: ""
            )
            keyboardStatus.isEnabled = false
            menu.addItem(keyboardStatus)
            hasContent = true
            if !CGPreflightListenEventAccess() {
                let permission = NSMenuItem(title: L10n.grantInputMonitoring, action: #selector(requestInputMonitoring), keyEquivalent: "")
                permission.target = self
                menu.addItem(permission)
            }
        }

        return hasContent
    }

    /// 未完成任务的聚合描述：最多列两个目标，其余折叠。
    private func refusedDetail(_ refused: [ScheduledAction]) -> String {
        let ordered = ScheduleDecision.ordered(refused)
        var parts: [String] = ordered.prefix(2).map { action in
            action.target.kind == .disk
                ? L10n.statusRefusedDisk(action.displayName)
                : L10n.statusRefusedApp(action.displayName)
        }
        if ordered.count > 2 {
            parts.append(L10n.statusRefusedMore(ordered.count - 2))
        }
        return parts.joined(separator: L10n.statusRefusedJoiner)
    }

    /// 有未完成任务时给菜单栏图标加一个小圆点，回来后一眼能看到。
    private func updateStatusItemBadge() {
        guard let button = statusItem?.button else { return }
        let refused = scheduledActions.actions.filter { $0.state == .refused }
        if refused.isEmpty {
            button.image = baseMenuBarIcon
            button.toolTip = L10n.appName
        } else {
            button.image = badgedMenuBarIcon
            button.toolTip = L10n.statusIncomplete(count: refused.count, detail: refusedDetail(refused))
        }
    }

    private func addGlobalSection(to menu: NSMenu) {
        let accessibilityGranted = AXIsProcessTrusted()
        let toggle = NSMenuItem(title: L10n.enable, action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = enabled ? .on : .off
        if !accessibilityGranted {
            toggle.attributedTitle = NSAttributedString(string: toggle.title, attributes: [.foregroundColor: NSColor.disabledControlTextColor])
        }
        menu.addItem(toggle)

        let login = NSMenuItem(title: L10n.login, action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
    }

    private func addAssistiveSection(to menu: NSMenu) {
        let accessibilityGranted = AXIsProcessTrusted()

        let keyboardToggle = NSMenuItem(title: L10n.keyboardTitle(pro: license.isEntitled), action: #selector(toggleKeyboard), keyEquivalent: "")
        keyboardToggle.target = self
        keyboardToggle.state = license.isEntitled && keyboardEnabled ? .on : .off
        if !accessibilityGranted {
            keyboardToggle.attributedTitle = NSAttributedString(string: keyboardToggle.title, attributes: [.foregroundColor: NSColor.disabledControlTextColor])
        }
        menu.addItem(keyboardToggle)

        let bundleID = lastActiveApplication?.bundleIdentifier
        let applicationName = lastActiveApplication?.localizedName
        let activeRules = store.activeRules
        let isExceptedByID = bundleID.map { activeRules.contains(AppRule(match: .bundleID, value: $0)) } ?? false
        let isExceptedByName = applicationName.map { activeRules.contains(AppRule(match: .applicationName, value: $0)) } ?? false
        if !isExceptedByID && !isExceptedByName {
            let addCurrent = NSMenuItem(
                title: L10n.addCurrentAppTitle(applicationName ?? L10n.currentApp, mode: store.mode, pro: license.isEntitled),
                action: #selector(addCurrentApplication),
                keyEquivalent: "")
            addCurrent.target = self
            addCurrent.isEnabled = bundleID != nil
            menu.addItem(addCurrent)
        }

        let settings = NSMenuItem(title: L10n.rulesTitle(pro: license.isEntitled), action: #selector(openExceptionsWindow), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
    }

    private func addAppScheduleSection(to menu: NSMenu) {
        let entitled = license.isEntitled
        let appActions = scheduledActions.actions.filter { $0.target.kind == .application }
        let suffix = entitled
            ? ScheduleDecision.topLevelSuffix(scheduledActions.actions, kind: .application, now: Date())
            : nil
        let entry = NSMenuItem(
            title: L10n.scheduleTitle(pro: entitled, suffix: suffix),
            action: nil,
            keyEquivalent: ""
        )

        if !entitled {
            entry.action = #selector(openLicenseWindow)
            entry.target = self
        } else if appActions.isEmpty {
            entry.action = #selector(openSchedulePanelForNewTimer)
            entry.target = self
        } else {
            entry.submenu = buildAppScheduleSubmenu()
        }

        scheduleEntryItem = entry
        menu.addItem(entry)

        // 快路径与入口并列，放在「定时退出应用」正下方；子菜单给出可选时长。
        if entitled,
           let application = lastActiveApplication,
           isSchedulable(application) {
            menu.addItem(scheduleQuickItem(for: application))
        }
    }

    private static let schedulePresets = [5, 15, 30, 60, 120]

    private func scheduleQuickItem(for application: NSRunningApplication) -> NSMenuItem {
        let item = NSMenuItem(
            title: L10n.scheduleFastTitle(application.localizedName ?? L10n.currentApp),
            action: nil,
            keyEquivalent: ""
        )
        // 总开关关闭时这是"执行"入口，直接置灰；状态段已说明原因。
        guard enabled else {
            item.isEnabled = false
            return item
        }

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let bundleID = application.bundleIdentifier ?? ""
        for minutes in Self.schedulePresets {
            let preset = NSMenuItem(
                title: L10n.schedulePresetTitle(minutes),
                action: #selector(startScheduledQuitFromPreset(_:)),
                keyEquivalent: ""
            )
            preset.target = self
            preset.representedObject = ["bundleID": bundleID, "minutes": minutes]
            submenu.addItem(preset)
        }
        submenu.addItem(.separator())
        let custom = NSMenuItem(
            title: L10n.scheduleCustom,
            action: #selector(openSchedulePanelForCurrentApp),
            keyEquivalent: ""
        )
        custom.target = self
        submenu.addItem(custom)

        item.submenu = submenu
        return item
    }

    private func buildAppScheduleSubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let appActions = scheduledActions.actions.filter { $0.target.kind == .application }
        for action in ScheduleDecision.ordered(appActions) {
            let item = NSMenuItem(title: scheduleRowTitle(for: action), action: nil, keyEquivalent: "")
            configure(actionRow: item, for: action)
            scheduleRows.append(ScheduleRow(id: action.id, name: action.displayName, kind: action.target.kind, item: item))
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        let add = NSMenuItem(title: L10n.scheduleAdd, action: #selector(openSchedulePanelForNewTimer), keyEquivalent: "")
        add.target = self
        submenu.addItem(add)

        if !appActions.isEmpty {
            let cancelAll = NSMenuItem(title: L10n.scheduleCancelAll, action: #selector(cancelAllAppScheduleActions), keyEquivalent: "")
            cancelAll.target = self
            submenu.addItem(cancelAll)
        }

        return submenu
    }

    // MARK: - 定时弹出硬盘

    @discardableResult
    private func addDiskScheduleSection(to menu: NSMenu) -> Bool {
        // 菜单只保留聚合入口；磁盘列表与全部操作都在面板里。
        guard !DiskCatalog.ejectableDisks().isEmpty else { return false }

        let entitled = license.isEntitled
        let diskActions = scheduledActions.actions.filter { $0.target.kind == .disk }
        let suffix = entitled
            ? ScheduleDecision.topLevelSuffix(scheduledActions.actions, kind: .disk, now: Date())
            : nil
        let entry = NSMenuItem(
            title: L10n.ejectTitle(pro: entitled, suffix: suffix),
            action: nil,
            keyEquivalent: ""
        )

        if !entitled {
            entry.action = #selector(openLicenseWindow)
            entry.target = self
        } else if diskActions.isEmpty {
            entry.action = #selector(openEjectPanelForNewDisk)
            entry.target = self
        } else {
            entry.submenu = buildDiskSubmenu()
        }
        ejectEntryItem = entry
        menu.addItem(entry)
        return true
    }

    private func buildDiskSubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let diskActions = scheduledActions.actions.filter { $0.target.kind == .disk }
        for action in ScheduleDecision.ordered(diskActions) {
            let item = NSMenuItem(title: diskRowTitle(for: action), action: nil, keyEquivalent: "")
            configure(actionRow: item, for: action)
            scheduleRows.append(ScheduleRow(id: action.id, name: action.displayName, kind: action.target.kind, item: item))
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        let add = NSMenuItem(title: L10n.ejectAdd, action: #selector(openEjectPanelForNewDisk), keyEquivalent: "")
        add.target = self
        submenu.addItem(add)

        if !diskActions.isEmpty {
            let cancelAll = NSMenuItem(title: L10n.scheduleCancelAll, action: #selector(cancelAllDiskScheduleActions), keyEquivalent: "")
            cancelAll.target = self
            submenu.addItem(cancelAll)
        }

        return submenu
    }

    private func configure(actionRow item: NSMenuItem, for action: ScheduledAction) {
        switch action.state {
        case .armed:
            item.target = self
            item.action = #selector(cancelScheduledAction(_:))
            item.representedObject = action.id.uuidString
            item.toolTip = L10n.scheduleCancelHint
        case .refused:
            item.target = self
            item.action = #selector(retryScheduledAction(_:))
            item.representedObject = action.id.uuidString
            item.toolTip = L10n.scheduleRetryHint
        case .firing:
            item.isEnabled = false
        }
    }

    private func addApplicationSection(to menu: NSMenu) {
        if !license.hasPro {
            let unlock = NSMenuItem(title: L10n.licenseMenuUnlock, action: #selector(openLicenseWindow), keyEquivalent: "")
            unlock.target = self
            menu.addItem(unlock)
        }

        let licenseItem = NSMenuItem(title: L10n.licenseMenuManage, action: #selector(openLicenseWindow), keyEquivalent: "")
        licenseItem.target = self
        menu.addItem(licenseItem)

        let about = NSMenuItem(title: L10n.about, action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: L10n.quit, action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - 定时退出的菜单刷新

    private func scheduleRowTitle(for action: ScheduledAction) -> String {
        switch action.state {
        case .armed:
            let remaining = ScheduleDecision.remainingText(fireAt: action.fireAt, now: Date())
            return L10n.scheduleRowTitle(name: action.displayName, remaining: remaining)
        case .refused:
            return L10n.scheduleRefusedTitle(action.displayName)
        case .firing:
            return L10n.scheduleFiringTitle(action.displayName)
        }
    }

    private func diskRowTitle(for action: ScheduledAction) -> String {
        switch action.state {
        case .armed:
            let now = Date()
            let remaining = ScheduleDecision.remainingText(fireAt: action.fireAt, now: now)
            guard action.mode == .idle else {
                return L10n.diskRowTitle(name: action.displayName, remaining: remaining)
            }
            if diskActivity.isRecentlyActive(bsdName: action.target.diskBSDName, now: now) {
                return L10n.diskIdleActiveTitle(action.displayName)
            }
            return L10n.diskIdleRowTitle(
                name: action.displayName,
                minutes: action.idleMinutes ?? 0,
                remaining: remaining
            )
        case .refused:
            return L10n.diskRefusedTitle(action.displayName)
        case .firing:
            return L10n.diskFiringTitle(action.displayName)
        }
    }

    /// 菜单打开期间只改标题，不增删条目，避免 menu tracking 期间的抖动。
    private func updateScheduleTitles() {
        let now = Date()
        let actions = scheduledActions.actions

        if let entry = scheduleEntryItem {
            let suffix = license.isEntitled
                ? ScheduleDecision.topLevelSuffix(actions, kind: .application, now: now)
                : nil
            entry.title = L10n.scheduleTitle(pro: license.isEntitled, suffix: suffix)
        }
        if let entry = ejectEntryItem {
            let suffix = license.isEntitled
                ? ScheduleDecision.topLevelSuffix(actions, kind: .disk, now: now)
                : nil
            entry.title = L10n.ejectTitle(pro: license.isEntitled, suffix: suffix)
        }

        for row in scheduleRows {
            guard let action = actions.first(where: { $0.id == row.id }) else {
                row.item.title = row.kind == .disk
                    ? L10n.diskEndedTitle(row.name)
                    : L10n.scheduleEndedTitle(row.name)
                row.item.isEnabled = false
                row.item.action = nil
                row.item.toolTip = nil
                continue
            }
            row.item.title = action.target.kind == .disk
                ? diskRowTitle(for: action)
                : scheduleRowTitle(for: action)
            switch action.state {
            case .armed:
                row.item.isEnabled = true
                row.item.action = #selector(cancelScheduledAction(_:))
                row.item.representedObject = action.id.uuidString
                row.item.toolTip = L10n.scheduleCancelHint
            case .refused:
                row.item.isEnabled = true
                row.item.action = #selector(retryScheduledAction(_:))
                row.item.representedObject = action.id.uuidString
                row.item.toolTip = L10n.scheduleRetryHint
            case .firing:
                row.item.isEnabled = false
                row.item.action = nil
                row.item.toolTip = nil
            }
        }

    }

    private func startMenuCountdown() {
        stopMenuCountdown()
        guard license.isEntitled, !scheduledActions.actions.isEmpty else { return }
        // 必须挂到 .common，否则菜单追踪期间 .default 模式下的定时器不会触发。
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateScheduleTitles() }
        }
        RunLoop.main.add(timer, forMode: .common)
        menuCountdownTimer = timer
    }

    private func stopMenuCountdown() {
        menuCountdownTimer?.invalidate()
        menuCountdownTimer = nil
    }

    @objc private func toggleEnabled() {
        guard AXIsProcessTrusted() else { showAccessibilityRequired(); return }
        if enabled {
            let active = scheduledActions.actions.filter { $0.state == .armed || $0.state == .refused }
            if active.isEmpty {
                setEnabled(false)
            } else if confirmDisabling(with: active) {
                setEnabled(false)
            }
        } else {
            setEnabled(true)
        }
    }

    /// 全局总开关：关闭时连同待执行的定时任务一起停掉。
    private func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "enabled")
        if value {
            _ = monitor.start()
        } else {
            scheduler.cancelAll()
            monitor.stop()
        }
        refreshMenu()
    }

    private func confirmDisabling(with actions: [ScheduledAction]) -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.scheduleConfirmTitle

        let now = Date()
        var lines = L10n.scheduleConfirmMessage(actions.count)
        for action in ScheduleDecision.ordered(actions).prefix(3) {
            switch (action.target.kind, action.state) {
            case (.application, .armed):
                lines += "\n" + L10n.scheduleRowTitle(
                    name: action.displayName,
                    remaining: ScheduleDecision.remainingText(fireAt: action.fireAt, now: now)
                )
            case (.application, .refused):
                lines += "\n" + L10n.scheduleRefusedTitle(action.displayName)
            case (.application, .firing):
                lines += "\n" + L10n.scheduleFiringTitle(action.displayName)
            case (.disk, .armed):
                lines += "\n" + diskRowTitle(for: action)
            case (.disk, .refused):
                lines += "\n" + L10n.diskRefusedTitle(action.displayName)
            case (.disk, .firing):
                lines += "\n" + L10n.diskFiringTitle(action.displayName)
            }
        }
        if actions.count > 3 {
            lines += "\n" + L10n.scheduleConfirmMore(actions.count - 3)
        }
        alert.informativeText = lines
        alert.addButton(withTitle: L10n.cancel)
        alert.addButton(withTitle: L10n.scheduleConfirmAction)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }

    // MARK: - 定时退出

    @objc private func openSchedulePanelForNewTimer() {
        guard license.isEntitled else { openLicenseWindow(); return }
        guard enabled else { showScheduleDisabledAlert(); return }
        presentSchedulePanel(preselecting: nil, minutes: 30)
    }

    @objc private func openSchedulePanelForCurrentApp() {
        guard license.isEntitled else { openLicenseWindow(); return }
        guard enabled else { showScheduleDisabledAlert(); return }
        guard let application = lastActiveApplication, isSchedulable(application) else { return }
        presentSchedulePanel(preselecting: application, minutes: 30, prefersCustom: true)
    }

    @objc private func startScheduledQuitFromPreset(_ sender: NSMenuItem) {
        guard license.isEntitled else { openLicenseWindow(); return }
        guard enabled else { return }
        guard let info = sender.representedObject as? [String: Any],
              let bundleID = info["bundleID"] as? String,
              let minutes = info["minutes"] as? Int,
              let application = NSRunningApplication
                  .runningApplications(withBundleIdentifier: bundleID)
                  .first else { return }
        startScheduledQuit(for: application, minutes: minutes)
    }

    @objc private func cancelScheduledAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return }
        scheduler.cancel(id: id)
    }

    @objc private func retryScheduledAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return }
        scheduler.retry(id: id)
    }

    @objc private func cancelAllAppScheduleActions() {
        cancelAllScheduleActions(kind: .application)
    }

    @objc private func cancelAllDiskScheduleActions() {
        cancelAllScheduleActions(kind: .disk)
    }

    private func cancelAllScheduleActions(kind: ScheduleTarget.Kind) {
        for action in scheduledActions.actions where action.target.kind == kind {
            scheduler.cancel(id: action.id)
        }
    }

    /// 定时退出的目标只能是有 Dock 图标的普通应用，且不能是自己或 Finder。
    private func isSchedulable(_ application: NSRunningApplication) -> Bool {
        guard let bundleID = application.bundleIdentifier else { return false }
        return application.activationPolicy == .regular
            && application != NSRunningApplication.current
            && bundleID != "com.apple.finder"
    }

    private func presentSchedulePanel(
        preselecting application: NSRunningApplication?,
        minutes: Int,
        prefersCustom: Bool = false
    ) {
        let applications = NSWorkspace.shared.runningApplications
            .filter { isSchedulable($0) }
            .sorted {
                ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending
            }

        let view = ScheduleEditorView(
            applications: applications,
            initialBundleID: application?.bundleIdentifier,
            initialMinutes: minutes,
            prefersCustomDuration: prefersCustom,
            onStart: { [weak self] target, minutes in
                self?.startScheduledQuit(for: target, minutes: minutes)
                self?.closeSchedulePanel()
            },
            onCancel: { [weak self] in self?.closeSchedulePanel() }
        )

        let window: NSWindow
        if let existing = scheduleWindow {
            window = existing
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 240),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = L10n.schedulePanelTitle
            window.center()
            scheduleWindow = window
        }

        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        window.contentView = hosting
        window.setContentSize(NSSize(width: 460, height: max(200, hosting.fittingSize.height)))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeSchedulePanel() {
        scheduleWindow?.orderOut(nil)
    }

    private func startScheduledQuit(for application: NSRunningApplication, minutes: Int) {
        guard let bundleID = application.bundleIdentifier else { return }
        scheduler.add(
            target: .application(bundleID),
            displayName: application.localizedName ?? bundleID,
            duration: TimeInterval(minutes * 60)
        )
    }

    // MARK: - 定时弹出硬盘

    /// 面板里的「立即弹出」：不创建规则，成功后关闭面板。
    private func ejectNow(_ disk: ScheduledDisk) {
        guard license.isEntitled else { openLicenseWindow(); return }
        guard enabled else { return }
        DiskEjector.eject(mainVolumePath: disk.mainVolumePath) { [weak self] success in
            guard let self else { return }
            if success {
                self.closeEjectPanel()
            } else {
                self.showEjectFailure(name: disk.displayName)
            }
        }
    }

    private func showEjectFailure(name: String) {
        let alert = NSAlert()
        alert.messageText = L10n.ejectFailedTitle(name)
        alert.informativeText = L10n.ejectFailedMessage
        alert.addButton(withTitle: L10n.okay)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openEjectPanelForNewDisk() {
        guard license.isEntitled else { openLicenseWindow(); return }
        guard enabled else { showScheduleDisabledAlert(); return }
        presentEjectPanel(preselecting: nil, minutes: 30)
    }

    private func presentEjectPanel(
        preselecting bsdName: String?,
        minutes: Int,
        prefersCustom: Bool = false
    ) {
        let disks = DiskCatalog.ejectableDisks()
        guard !disks.isEmpty else { return }

        let diskRules = Dictionary(
            uniqueKeysWithValues: scheduledActions.actions
                .filter { $0.target.kind == .disk }
                .map { ($0.target.identifier, $0) }
        )
        let idleSupport = Dictionary(
            uniqueKeysWithValues: disks.map {
                ($0.bsdName, diskActivity.supportsActivity(bsdName: $0.bsdName))
            }
        )
        let initialDisk = disks.first { $0.bsdName == bsdName } ?? disks.first
        let initialRule = initialDisk.flatMap { diskRules[$0.mainVolumePath] }
        let initialMode = initialRule?.mode ?? .timed
        let initialMinutes: Int = {
            guard let initialRule else { return minutes }
            if let idle = initialRule.idleMinutes { return idle }
            let remaining = Int((initialRule.fireAt.timeIntervalSinceNow / 60).rounded())
            return max(1, remaining)
        }()

        let view = EjectPanelView(
            disks: disks,
            initialDiskID: bsdName ?? disks.first?.bsdName,
            initialMode: initialMode,
            initialMinutes: initialMinutes,
            prefersCustomDuration: prefersCustom,
            scheduledActions: scheduledActions,
            idleSupport: idleSupport,
            onStart: { [weak self] disk, mode, minutes in
                self?.startDiskEject(
                    bsdName: disk.bsdName,
                    mainVolumePath: disk.mainVolumePath,
                    displayName: disk.displayName,
                    minutes: minutes,
                    mode: mode
                )
                self?.closeEjectPanel()
            },
            onEjectNow: { [weak self] disk in self?.ejectNow(disk) },
            onCancelRule: { [weak self] action in self?.scheduler.cancel(id: action.id) },
            onCancel: { [weak self] in self?.closeEjectPanel() }
        )

        let window: NSWindow
        if let existing = ejectWindow {
            window = existing
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 240),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = L10n.ejectPanelTitle
            window.center()
            ejectWindow = window
        }

        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        window.contentView = hosting
        window.setContentSize(NSSize(width: 460, height: max(200, hosting.fittingSize.height)))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeEjectPanel() {
        ejectWindow?.orderOut(nil)
    }

    private func startDiskEject(
        bsdName: String,
        mainVolumePath: String,
        displayName: String,
        minutes: Int,
        mode: ScheduleMode
    ) {
        scheduler.add(
            target: .disk(mainVolumePath: mainVolumePath, bsdName: bsdName),
            displayName: displayName,
            duration: TimeInterval(minutes * 60),
            mode: mode
        )
    }

    // MARK: - 调度器桥接

    /// 闲置规则的活动探测：读不到整盘计数时按「有活动」处理，绝不据此弹盘。
    private func isDiskActive(_ action: ScheduledAction) -> Bool {
        guard action.mode == .idle, let bsdName = action.target.diskBSDName else { return true }
        return diskActivity.hasActivity(bsdName: bsdName)
    }

    private func isTargetAvailable(_ action: ScheduledAction) -> Bool {
        switch action.target.kind {
        case .application:
            return AppTerminator.isRunning(bundleID: action.target.identifier)
        case .disk:
            return DiskCatalog.isVolumeMounted(path: action.target.identifier)
        }
    }

    private func isTargetStillPresent(_ action: ScheduledAction) -> Bool {
        switch action.target.kind {
        case .application:
            return AppTerminator.isRunning(bundleID: action.target.identifier)
        case .disk:
            if let bsdName = action.target.diskBSDName, DiskCatalog.isDiskPresent(bsdName: bsdName) {
                return true
            }
            return DiskCatalog.isVolumeMounted(path: action.target.identifier)
        }
    }

    private func perform(_ action: ScheduledAction, completion: @escaping (Bool) -> Void) {
        switch action.target.kind {
        case .application:
            completion(AppTerminator.quit(bundleID: action.target.identifier))
        case .disk:
            let path = action.target.identifier
            guard DiskCatalog.isVolumeMounted(path: path) else {
                completion(false)
                return
            }
            DiskEjector.eject(mainVolumePath: path, completion: completion)
        }
    }

    private func showScheduleDisabledAlert() {
        let alert = NSAlert()
        alert.messageText = L10n.scheduleDisabledTitle
        alert.informativeText = L10n.scheduleDisabledMessage
        alert.addButton(withTitle: L10n.cancel)
        alert.addButton(withTitle: L10n.scheduleDisabledAction)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            setEnabled(true)
            presentSchedulePanel(preselecting: nil, minutes: 30)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopMenuCountdown()
        authorizationTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    @objc private func toggleKeyboard() {
        guard license.isEntitled else { openLicenseWindow(); return }
        guard AXIsProcessTrusted() else { showAccessibilityRequired(); return }
        keyboardEnabled.toggle()
        UserDefaults.standard.set(keyboardEnabled, forKey: "keyboardEnabled")
        monitor.setKeyboardEnabled(keyboardEnabled)
        refreshMenu()
    }

    private func showRuleGuideWhenReady() {
        guard store.needsOnboarding else { return }
        guard NSApp.modalWindow == nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showRuleGuideWhenReady() }
            return
        }
        openRuleGuide()
    }

    @objc private func openRuleGuide() {
        if onboardingWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = NSLocalizedString("onboarding.title", comment: "")
            window.contentView = NSHostingView(rootView: RuleGuideView(store: store, finish: { [weak self] edit in
                self?.store.finishOnboarding()
                self?.onboardingWindow?.close()
                if edit { self?.openExceptionsWindow() }
            }))
            onboardingCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.store.finishOnboarding() }
            }
            window.center()
            onboardingWindow = window
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openExceptionsWindow() {
        guard license.isEntitled else { openLicenseWindow(); return }
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = L10n.rulesWindow
            let hostingView = NSHostingView(rootView: SettingsView(store: store))
            let preferredWidth: CGFloat = 560
            hostingView.frame = NSRect(x: 0, y: 0, width: preferredWidth, height: 440)
            hostingView.layoutSubtreeIfNeeded()
            window.contentView = hostingView
            settingsHostingView = hostingView
            let fittingSize = hostingView.fittingSize
            window.setContentSize(NSSize(
                width: preferredWidth,
                height: max(440, fittingSize.height)
            ))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 模式切换或语言变化可能改变文案换行，重新按 SwiftUI 内容高度调整窗口。
    private func sizeSettingsWindow() {
        guard let window = settingsWindow, let hostingView = settingsHostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let contentHeight = max(440, hostingView.fittingSize.height)
        guard abs(window.contentLayoutRect.height - contentHeight) > 0.5 else { return }
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(NSSize(width: window.contentLayoutRect.width, height: contentHeight))
        window.setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y - window.frame.height))
    }

    @objc private func addCurrentApplication() {
        guard license.isEntitled else { openLicenseWindow(); return }
        guard let bundleID = lastActiveApplication?.bundleIdentifier else { return }
        store.addApplication(bundleID: bundleID)
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showError(L10n.loginSettingsError, error)
        }
        refreshMenu()
    }

    @objc private func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showAccessibilityRequired() {
        let alert = NSAlert()
        alert.messageText = L10n.accessibilityTitle
        alert.informativeText = L10n.accessibilityMessage
        alert.addButton(withTitle: L10n.openSystemSettings)
        alert.addButton(withTitle: L10n.cancel)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            requestAccessibility()
        }
    }

    @objc private func requestInputMonitoring() {
        if CGRequestListenEventAccess() {
            monitor.retryKeyboard()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
        refreshMenu()
    }

    @objc private func openLicenseWindow() {
        if licenseWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.licenseMenuManage
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: LicenseView(manager: license))
            window.center()
            licenseWindow = window
        }
        licenseWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var licenseSummaryTitle: String {
        switch license.tier {
        case .pro: return L10n.licenseMenuPro
        case .trial(let days): return L10n.licenseMenuTrial(days)
        case .free: return L10n.licenseMenuFree
        }
    }

    private func applyLicenseState() {
        monitor.setKeyboardEnabled(license.isEntitled && keyboardEnabled)
        refreshMenu()
    }

    @objc private func showAbout() {
        if aboutWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.aboutTitle
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: AboutView(updaterController: updaterController))
            window.center()
            aboutWindow = window
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        monitor.stop()
        NSApp.terminate(nil)
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

private struct AboutView: View {
    let updaterController: SPUStandardUpdaterController
    @State private var iconRefreshID = 0
    @State private var autoCheckUpdates: Bool

    init(updaterController: SPUStandardUpdaterController) {
        self.updaterController = updaterController
        _autoCheckUpdates = State(
            initialValue: updaterController.updater.automaticallyChecksForUpdates)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        return L10n.version(version, build: build)
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                AboutAppIcon(refreshID: iconRefreshID)
                    .frame(width: 80, height: 80)
                Text(L10n.appName).font(.title2.bold())
                Text(version).font(.callout).foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Button(L10n.checkForUpdates) {
                    updaterController.checkForUpdates(nil)
                }
                .controlSize(.small)

                Toggle(L10n.automaticUpdates, isOn: $autoCheckUpdates)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .onChange(of: autoCheckUpdates) { newValue in
                        updaterController.updater.automaticallyChecksForUpdates = newValue
                    }
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.aboutDescription1)
                    Text(L10n.aboutDescription2)
                        .foregroundStyle(.secondary)
                    Text(L10n.aboutDescription3)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.credits).font(.headline)
                    HStack(alignment: .top, spacing: 12) {
                        Link("@hahahhqyou", destination: URL(string: "https://github.com/hahahhqyou")!)
                    }
                    .font(.callout)
                }

                Divider()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Link(L10n.repository, destination: URL(string: "https://github.com/yinzhenyu-su/mac-scripts")!)
                .font(.callout)
        }
        .padding(28)
        .frame(width: 440, height: 520)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            iconRefreshID += 1
        }
    }
}

private struct AboutAppIcon: NSViewRepresentable {
    let refreshID: Int

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        // 使用系统文件图标，让 Icon Services 按图标外观设置绘制当前变体。
        view.image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}
