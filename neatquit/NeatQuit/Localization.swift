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
