import AppKit
import ApplicationServices
import ServiceManagement
import Sparkle
import SwiftUI

@main
struct SmartCloseMain {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = SmartCloseAppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}

@MainActor
final class SmartCloseAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = CloseMonitor()
    private let store = RuleStore()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var lastActiveApplication: NSRunningApplication?
    private var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
    private var keyboardEnabled = UserDefaults.standard.bool(forKey: "keyboardEnabled")
    private var accessibilityWasTrusted = AXIsProcessTrusted()
    private var inputMonitoringWasGranted = CGPreflightListenEventAccess()
    private var authorizationTimer: Timer?
    private var restartInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        monitor.updateRules(store.rules)
        monitor.setKeyboardEnabled(keyboardEnabled)
        store.onChange = { [weak self] rules in self?.monitor.updateRules(rules) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true
            image.size = NSSize(width: 24, height: 24)
            statusItem.button?.image = image
        }
        statusItem.button?.toolTip = "智能退出"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        if enabled { _ = monitor.start() }
        refreshMenu()

        authorizationTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(checkAccessibilityAuthorization),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func checkAccessibilityAuthorization() {
        let inputMonitoringGranted = CGPreflightListenEventAccess()
        if inputMonitoringGranted != inputMonitoringWasGranted {
            inputMonitoringWasGranted = inputMonitoringGranted
            if inputMonitoringGranted { monitor.retryKeyboard() }
            refreshMenu()
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
        refreshMenu()
    }

    private func refreshMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        let accessibilityGranted = AXIsProcessTrusted()
        let status = !accessibilityGranted ? "需要辅助功能权限" : (!enabled ? "已暂停" : (monitor.isRunning ? "智能退出已启用" : "事件监听启动失败"))
        let statusItem = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "启用智能退出", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = enabled ? .on : .off
        if !accessibilityGranted {
            toggle.attributedTitle = NSAttributedString(string: toggle.title, attributes: [.foregroundColor: NSColor.disabledControlTextColor])
        }
        menu.addItem(toggle)

        let keyboardToggle = NSMenuItem(title: "⌘W 智能退出", action: #selector(toggleKeyboard), keyEquivalent: "")
        keyboardToggle.target = self
        keyboardToggle.state = keyboardEnabled ? .on : .off
        if !accessibilityGranted {
            keyboardToggle.attributedTitle = NSAttributedString(string: keyboardToggle.title, attributes: [.foregroundColor: NSColor.disabledControlTextColor])
        }
        menu.addItem(keyboardToggle)

        if enabled && keyboardEnabled && accessibilityGranted && !monitor.isKeyboardRunning {
            let keyboardStatus = NSMenuItem(
                title: CGPreflightListenEventAccess() ? "⌘W 监听启动失败" : "⌘W 需要输入监控权限",
                action: nil,
                keyEquivalent: ""
            )
            keyboardStatus.isEnabled = false
            menu.addItem(keyboardStatus)
            if !CGPreflightListenEventAccess() {
                let permission = NSMenuItem(title: "授予输入监控权限…", action: #selector(requestInputMonitoring), keyEquivalent: "")
                permission.target = self
                menu.addItem(permission)
            }
        }

        let login = NSMenuItem(title: "登录时启动", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let bundleID = lastActiveApplication?.bundleIdentifier
        let applicationName = lastActiveApplication?.localizedName
        let isExceptedByID = bundleID.map { store.rules.contains(AppRule(match: .bundleID, value: $0)) } ?? false
        let isExceptedByName = applicationName.map { store.rules.contains(AppRule(match: .applicationName, value: $0)) } ?? false
        if !isExceptedByID && !isExceptedByName {
            let addCurrent = NSMenuItem(title: "将 \(applicationName ?? "当前 App") 加入例外", action: #selector(addCurrentApplication), keyEquivalent: "")
            addCurrent.target = self
            addCurrent.isEnabled = bundleID != nil
            menu.addItem(addCurrent)
        }

        let settings = NSMenuItem(title: "例外应用…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        if !accessibilityGranted {
            let permission = NSMenuItem(title: "授予辅助功能权限…", action: #selector(requestAccessibility), keyEquivalent: "")
            permission.target = self
            menu.addItem(permission)
        }
        menu.addItem(.separator())

        let about = NSMenuItem(title: "关于智能退出", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "退出应用", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() {
        guard AXIsProcessTrusted() else { showAccessibilityRequired(); return }
        enabled.toggle()
        UserDefaults.standard.set(enabled, forKey: "enabled")
        if enabled { _ = monitor.start() } else { monitor.stop() }
        refreshMenu()
    }

    @objc private func toggleKeyboard() {
        guard AXIsProcessTrusted() else { showAccessibilityRequired(); return }
        keyboardEnabled.toggle()
        UserDefaults.standard.set(keyboardEnabled, forKey: "keyboardEnabled")
        monitor.setKeyboardEnabled(keyboardEnabled)
        refreshMenu()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = "例外应用设置"
            window.contentView = NSHostingView(rootView: SettingsView(store: store))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func addCurrentApplication() {
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
            showError("无法更改登录启动设置", error)
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
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "请在系统设置的“隐私与安全性”→“辅助功能”中允许“智能退出”。授权后应用会自动重新启动。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
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

    @objc private func showAbout() {
        if aboutWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "关于智能退出"
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
        return "版本 \(version)（\(build)）"
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                AboutAppIcon(refreshID: iconRefreshID)
                    .frame(width: 80, height: 80)
                Text("智能退出").font(.title2.bold())
                Text(version).font(.callout).foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Button("检查更新") {
                    updaterController.checkForUpdates(nil)
                }
                .controlSize(.small)

                Toggle("自动检查更新", isOn: $autoCheckUpdates)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .onChange(of: autoCheckUpdates) { newValue in
                        updaterController.updater.automaticallyChecksForUpdates = newValue
                    }
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("关闭最后一个窗口时自动退出应用。")
                    Text("支持红色关闭按钮与可选的 ⌘W；例外应用仅关闭窗口。")
                        .foregroundStyle(.secondary)
                    Text("本软件需要授予辅助功能权限以识别窗口和 ⌘W 快捷键。")
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("致谢名单").font(.headline)
                    HStack(alignment: .top, spacing: 12) {
                        Link("@hahahhqyou", destination: URL(string: "https://github.com/hahahhqyou")!)
                    }
                    .font(.callout)
                }

                Divider()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Link("项目仓库 ↗", destination: URL(string: "https://github.com/yinzhenyu-su/mac-scripts")!)
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
