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
    static let exceptions = text("menu.exceptions")
    static let grantAccessibility = text("menu.grantAccessibility")
    static let about = text("menu.about")
    static let quit = text("menu.quit")
    static let exceptionsWindow = text("window.exceptions")
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
    static let remove = text("settings.remove")
    static let addApp = text("settings.addApp")
    static let settingsFooter = text("settings.footer")
    static let cannotAddApp = text("settings.cannotAddApp")
    static let okay = text("common.okay")
    static let chooseAppMessage = text("settings.chooseAppMessage")

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
    static let exceptionsPro = text("menu.exceptions.pro")
    static let addCurrentPro = text("menu.addCurrent.pro")

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

    static func exceptionsTitle(pro: Bool) -> String {
        pro ? exceptions : exceptionsPro
    }

    static func addCurrentAppTitle(_ name: String, pro: Bool) -> String {
        String(format: pro ? text("menu.addCurrent") : addCurrentPro, name)
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
