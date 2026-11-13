import Foundation

enum L10n {
    private static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: .main, comment: "")
    }

    static let appName = text("app.name")
    static let accessibilityRequired = text("status.accessibilityRequired")
    static let paused = text("status.paused")
    static let enabled = text("status.enabled")
    static let listenerFailed = text("status.listenerFailed")
    static let enable = text("menu.enable")
    static let keyboard = text("menu.keyboard")
    static let keyboardFailed = text("menu.keyboardFailed")
    static let keyboardPermissionRequired = text("menu.keyboardPermissionRequired")
    static let grantInputMonitoring = text("menu.grantInputMonitoring")
    static let login = text("menu.login")
    static let currentApp = text("app.current")
    static let grantAccessibility = text("menu.grantAccessibility")
    static let about = text("menu.about")
    static let quit = text("menu.quit")
    static let rulesWindow = text("window.rules")
    static let loginSettingsError = text("error.loginSettings")
    static let accessibilityTitle = text("accessibility.title")
    static let accessibilityMessage = text("accessibility.message")
    static let openSystemSettings = text("accessibility.openSystemSettings")
    static let cancel = text("common.cancel")
    static let aboutTitle = text("about.title")
    static let checkForUpdates = text("about.checkForUpdates")
    static let automaticUpdates = text("about.automaticUpdates")
    static let aboutDescription1 = text("about.description1")
    static let aboutDescription2 = text("about.description2")
    static let aboutDescription3 = text("about.description3")
    static let credits = text("about.credits")
    static let repository = text("about.repository")
    static let settingsTitle = text("settings.title")
    static let settingsDescription = text("settings.description")
    static let settingsModeLabel = text("settings.mode.label")
    static let settingsModeExclude = text("settings.mode.exclude")
    static let settingsModeOnly = text("settings.mode.only")
    static let remove = text("settings.remove")
    static let addApp = text("settings.addApp")
    static let cannotAddApp = text("settings.cannotAddApp")
    static let okay = text("common.okay")
    static let settingsSearchPlaceholder = text("settings.search.placeholder")
    static let settingsClearSearch = text("settings.search.clear")
    static let settingsNoResults = text("settings.search.noResults")

    // 定时退出
    static let scheduleEntryBase = text("menu.schedule")
    static let scheduleEntryFormat = text("menu.schedule.entry")
    static let scheduleEntryPro = text("menu.schedule.pro")
    static let scheduleFastFormat = text("menu.schedule.fast")
    static let scheduleAdd = text("menu.schedule.add")
    static let scheduleCancelAll = text("menu.schedule.cancelAll")
    static let scheduleRowFormat = text("menu.schedule.row")
    static let scheduleRefusedFormat = text("menu.schedule.refused")
    static let scheduleFiringFormat = text("menu.schedule.firing")
    static let scheduleEndedFormat = text("menu.schedule.ended")
    static let scheduleRetryHint = text("menu.schedule.retryHint")
    static let scheduleCancelHint = text("menu.schedule.cancelHint")
    static let schedulePanelTitle = text("schedule.panel.title")
    static let schedulePanelApp = text("schedule.panel.app")
    static let schedulePanelDuration = text("schedule.panel.duration")
    static let schedulePanelMinutes = text("schedule.panel.minutes")
    static let schedulePanelCustom = text("schedule.panel.custom")
    static let schedulePanelNote = text("schedule.panel.note")
    static let schedulePanelStart = text("schedule.panel.start")
    static let schedulePanelInvalid = text("schedule.panel.invalid")
    static let schedulePanelNoApps = text("schedule.panel.noApps")
    static let scheduleDisabledTitle = text("schedule.disabled.title")
    static let scheduleDisabledMessage = text("schedule.disabled.message")
    static let scheduleDisabledAction = text("schedule.disabled.action")
    static let scheduleConfirmTitle = text("schedule.confirm.title")
    static let scheduleConfirmMessageFormat = text("schedule.confirm.message")
    static let scheduleConfirmMoreFormat = text("schedule.confirm.more")
    static let scheduleConfirmAction = text("schedule.confirm.action")

    static func scheduleTitle(pro: Bool, suffix: String?) -> String {
        guard pro else { return scheduleEntryPro }
        guard let suffix else { return scheduleEntryBase }
        return String(format: scheduleEntryFormat, suffix)
    }

    static func scheduleFastTitle(_ name: String) -> String {
        String(format: scheduleFastFormat, name)
    }

    static func schedulePresetTitle(_ minutes: Int) -> String {
        switch minutes {
        case 5: return text("schedule.preset.5")
        case 15: return text("schedule.preset.15")
        case 30: return text("schedule.preset.30")
        case 60: return text("schedule.preset.60")
        case 120: return text("schedule.preset.120")
        default: return String(format: text("schedule.preset.minutes"), minutes)
        }
    }

    static let scheduleCustom = text("schedule.preset.custom")

    static func scheduleRowTitle(name: String, remaining: String) -> String {
        String(format: scheduleRowFormat, name, remaining)
    }

    static func scheduleRefusedTitle(_ name: String) -> String {
        String(format: scheduleRefusedFormat, name)
    }

    static func scheduleFiringTitle(_ name: String) -> String {
        String(format: scheduleFiringFormat, name)
    }

    static func scheduleEndedTitle(_ name: String) -> String {
        String(format: scheduleEndedFormat, name)
    }

    static func scheduleConfirmMessage(_ count: Int) -> String {
        String(format: scheduleConfirmMessageFormat, count)
    }

    static func scheduleConfirmMore(_ count: Int) -> String {
        String(format: scheduleConfirmMoreFormat, count)
    }

    // 定时弹出硬盘
    static let ejectEntryBase = text("menu.eject")
    static let ejectEntryFormat = text("menu.eject.entry")
    static let ejectEntryPro = text("menu.eject.pro")
    static let ejectAdd = text("menu.eject.add")
    static let ejectRowFormat = text("menu.eject.row")
    static let ejectRefusedFormat = text("menu.eject.refused")
    static let ejectFiringFormat = text("menu.eject.firing")
    static let ejectEndedFormat = text("menu.eject.ended")
    static let ejectPanelTitle = text("eject.panel.title")
    static let ejectPanelDisk = text("eject.panel.disk")
    static let ejectPanelNote = text("eject.panel.note")
    static let ejectPanelNoDisks = text("eject.panel.noDisks")
    static let ejectPanelMode = text("eject.panel.mode")
    static let ejectPanelModeTimed = text("eject.panel.mode.timed")
    static let ejectPanelModeIdle = text("eject.panel.mode.idle")
    static let ejectPanelIdleDuration = text("eject.panel.idleDuration")
    static let ejectPanelIdleUnsupported = text("eject.panel.idleUnsupported")
    static let ejectPanelCurrentRule = text("eject.panel.currentRule")
    static let ejectPanelCancelRule = text("eject.panel.cancelRule")
    static let ejectPanelStartTimed = text("eject.panel.start.timed")
    static let ejectPanelStartIdle = text("eject.panel.start.idle")
    static let close = text("common.close")
    static let ejectNow = text("menu.eject.now")
    static let statusRefusedJoiner = text("status.refused.joiner")
    static let ejectFailedMessage = text("eject.failed.message")

    static func ejectTitle(pro: Bool, suffix: String?) -> String {
        guard pro else { return ejectEntryPro }
        guard let suffix else { return ejectEntryBase }
        return String(format: ejectEntryFormat, suffix)
    }

    static func diskRowTitle(name: String, remaining: String) -> String {
        String(format: ejectRowFormat, name, remaining)
    }

    static func diskIdleRowTitle(name: String, minutes: Int, remaining: String) -> String {
        String(format: text("menu.eject.row.idle"), name, minutes, remaining)
    }

    static func diskIdleActiveTitle(_ name: String) -> String {
        String(format: text("menu.eject.row.idleActive"), name)
    }

    static func diskAccessTitle(_ name: String) -> String {
        String(format: text("disk.access.title"), name)
    }

    static let diskAccessMessage = text("disk.access.message")
    static let diskAccessOpenSettings = text("disk.access.openSettings")

    static let diskAccessIntroTitle = text("disk.access.intro.title")
    static let diskAccessContinue = text("disk.access.continue")

    static func diskAccessIntroMessage(_ name: String) -> String {
        String(format: text("disk.access.intro.message"), name)
    }

    static func ejectPanelIdleNote(minutes: Int) -> String {
        String(format: text("eject.panel.note.idle"), minutes)
    }

    static func ejectPanelCurrentIdle(minutes: Int, remaining: String) -> String {
        String(format: text("eject.panel.current.idle"), minutes, remaining)
    }

    static func ejectPanelCurrentTimed(remaining: String) -> String {
        String(format: text("eject.panel.current.timed"), remaining)
    }

    static func diskRefusedTitle(_ name: String) -> String {
        String(format: ejectRefusedFormat, name)
    }

    static func diskFiringTitle(_ name: String) -> String {
        String(format: ejectFiringFormat, name)
    }

    static func diskEndedTitle(_ name: String) -> String {
        String(format: ejectEndedFormat, name)
    }

    static func statusIncomplete(count: Int, detail: String) -> String {
        String(format: text("status.incomplete.title"), count, detail)
    }

    static func statusRefusedApp(_ name: String) -> String {
        String(format: text("status.refused.app"), name)
    }

    static func statusRefusedDisk(_ name: String) -> String {
        String(format: text("status.refused.disk"), name)
    }

    static func statusRefusedMore(_ count: Int) -> String {
        String(format: text("status.refused.more"), count)
    }

    static func ejectFailedTitle(_ name: String) -> String {
        String(format: text("eject.failed.title"), name)
    }

    static let menuEdit = text("menu.edit")
    static let menuUndo = text("menu.undo")
    static let menuRedo = text("menu.redo")
    static let menuCut = text("menu.cut")
    static let menuCopy = text("menu.copy")
    static let menuPaste = text("menu.paste")
    static let menuSelectAll = text("menu.selectAll")
    static let licensePaste = text("license.paste")

    static let licenseProTitle = text("license.pro.title")
    static let licenseProDetail = text("license.pro.detail")
    static let licenseFreeTitle = text("license.free.title")
    static let licenseFreeDetail = text("license.free.detail")
    static let licenseTrialDetail = text("license.trial.detail")
    static let licenseKeyLabel = text("license.key.label")
    static let licenseInputLabel = text("license.input.label")
    static let licenseInputPlaceholder = text("license.input.placeholder")
    static let licenseActivate = text("license.activate")
    static let licenseDeactivate = text("license.deactivate")
    static let licenseRefresh = text("license.refresh")
    static let licenseDeactivateConfirmTitle = text("license.deactivate.title")
    static let licenseDeactivateConfirmMessage = text("license.deactivate.message")
    static let licensePurchaseTitle = text("license.purchase.title")
    static let licensePurchaseDetail = text("license.purchase.detail")
    static let licenseFeatureKeyboard = text("license.feature.keyboard")
    static let licenseFeatureExceptions = text("license.feature.exceptions")
    static let licenseFeatureDevices = text("license.feature.devices")
    static let licensePurchaseButton = text("license.purchase.button")
    static let licensePurchaseNote = text("license.purchase.note")
    static let licenseErrorFormat = text("license.error.format")
    static let licenseErrorInvalid = text("license.error.invalid")
    static let licenseErrorLimit = text("license.error.limit")
    static let licenseErrorExpired = text("license.error.expired")
    static let licenseErrorDisabled = text("license.error.disabled")
    static let licenseErrorInactive = text("license.error.inactive")
    static let licenseErrorRate = text("license.error.rate")
    static let licenseErrorNetwork = text("license.error.network")
    static let licenseErrorGeneric = text("license.error.generic")
    static let licenseMenuPro = text("menu.license.pro")
    static let licenseMenuFree = text("menu.license.free")
    static let licenseMenuUnlock = text("menu.license.unlock")
    static let licenseMenuManage = text("menu.license.manage")
    static let keyboardPro = text("menu.keyboard.pro")

    static func licenseTrialTitle(_ days: Int) -> String {
        String(format: text("license.trial.title"), days)
    }

    static func licenseMenuTrial(_ days: Int) -> String {
        String(format: text("menu.license.trial"), days)
    }

    static func licenseActivationCount(_ used: Int, _ limit: Int) -> String {
        String(format: text("license.activation.count"), used, limit)
    }

    static func keyboardTitle(pro: Bool) -> String {
        pro ? keyboard : keyboardPro
    }

    static func rulesTitle(pro: Bool) -> String {
        pro ? text("menu.rules") : text("menu.rules.pro")
    }

    static func settingsFooter(mode: RuleMode) -> String {
        mode == .allExceptListed ? text("settings.footer.exclude") : text("settings.footer.only")
    }

    static func settingsEmpty(mode: RuleMode) -> String {
        mode == .allExceptListed ? text("settings.empty.exclude") : text("settings.empty.only")
    }

    static func chooseAppMessage(mode: RuleMode) -> String {
        mode == .allExceptListed ? text("settings.chooseAppMessage.exclude") : text("settings.chooseAppMessage.only")
    }

    static func addCurrentAppTitle(_ name: String, mode: RuleMode, pro: Bool) -> String {
        let key: String
        switch (mode, pro) {
        case (.allExceptListed, true): key = "menu.addCurrent"
        case (.allExceptListed, false): key = "menu.addCurrent.pro"
        case (.onlyListed, true): key = "menu.addCurrent.only"
        case (.onlyListed, false): key = "menu.addCurrent.only.pro"
        }
        return String(format: text(key), name)
    }


    static func status(for accessibilityGranted: Bool, enabled: Bool, monitorRunning: Bool) -> String {
        if !accessibilityGranted { return accessibilityRequired }
        if !enabled { return paused }
        return monitorRunning ? self.enabled : listenerFailed
    }

    static func addCurrentApp(_ name: String) -> String {
        String(format: text("menu.addCurrent"), name)
    }

    static func version(_ version: String, build: String) -> String {
        String(format: text("about.version"), version, build)
    }
}
