import AppKit
import ApplicationServices
import OSLog

final class CloseMonitor {
    private let logger = Logger(subsystem: "com.yinzhenyu.smartclose", category: "CloseMonitor")
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyboardEventTap: CFMachPort?
    private var keyboardRunLoopSource: CFRunLoopSource?
    private var keyboardEnabled = false
    private var keyboardRequestID = 0
    private var pendingClose: Target?
    private var pendingFullScreenClose: Target?
    private var fullScreenRequestID = 0
    private var rules: Set<AppRule> = []

    var isRunning: Bool { eventTap != nil }
    var isKeyboardRunning: Bool { keyboardEventTap != nil }

    func updateRules(_ rules: Set<AppRule>) {
        self.rules = rules
    }

    func setKeyboardEnabled(_ enabled: Bool) {
        keyboardEnabled = enabled
        if enabled { retryKeyboard() } else { stopKeyboard() }
    }

    func retryKeyboard() {
        guard keyboardEnabled, eventTap != nil, keyboardEventTap == nil else { return }
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<CloseMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handleKeyboard(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        keyboardEventTap = tap
        keyboardRunLoopSource = source
    }

    private func stopKeyboard() {
        keyboardRequestID &+= 1
        if let source = keyboardRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let keyboardEventTap { CGEvent.tapEnable(tap: keyboardEventTap, enable: false) }
        keyboardRunLoopSource = nil
        keyboardEventTap = nil
    }

    func start() -> Bool {
        guard eventTap == nil, AXIsProcessTrusted() else { return false }
        let mask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseDragged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<CloseMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        retryKeyboard()
        return true
    }

    func stop() {
        stopKeyboard()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        runLoopSource = nil
        eventTap = nil
        pendingClose = nil
        pendingFullScreenClose = nil
        fullScreenRequestID &+= 1
    }

    private func handleKeyboard(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let keyboardEventTap { CGEvent.tapEnable(tap: keyboardEventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown,
              let keyEvent = NSEvent(cgEvent: event),
              !keyEvent.isARepeat,
              keyEvent.modifierFlags.intersection([.command, .control, .option, .shift]) == [.command],
              keyEvent.charactersIgnoringModifiers?.lowercased() == "w",
              let application = NSWorkspace.shared.frontmostApplication,
              application != NSRunningApplication.current else {
            return Unmanaged.passUnretained(event)
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.15)
        guard let focusedWindow: AXUIElement = attribute(kAXFocusedWindowAttribute, from: appElement),
              stringAttribute(kAXSubroleAttribute, from: focusedWindow) == kAXStandardWindowSubrole as String,
              let windows: [AXUIElement] = attribute(kAXWindowsAttribute, from: appElement),
              windows.contains(where: { CFEqual($0, focusedWindow) }) else {
            return Unmanaged.passUnretained(event)
        }

        let isFullScreen = attribute("AXFullScreen", from: focusedWindow) as Bool? == true
        if isFullScreen {
            guard CloseDecision.shouldMonitorFullScreenClose(
                bundleID: application.bundleIdentifier,
                applicationName: application.localizedName,
                isStandardWindow: true,
                rules: rules
            ), let visibleWindowCount = visibleWindowCount(for: application.processIdentifier),
               visibleWindowCount > 0,
               let closingWindowID = screenSizedWindowID(for: application.processIdentifier) else { return Unmanaged.passUnretained(event) }
            fullScreenRequestID &+= 1
            logger.info("close candidate: source=keyboard kind=fullScreen pid=\(application.processIdentifier, privacy: .public) windowID=\(closingWindowID, privacy: .public)")
            scheduleFullScreenCheck(for: application, closingWindowID: closingWindowID, requestID: fullScreenRequestID, attempt: 0, sawNoWindows: false)
            return Unmanaged.passUnretained(event)
        }

        let standardWindowCount = windows.filter {
            stringAttribute(kAXSubroleAttribute, from: $0) == kAXStandardWindowSubrole as String
        }.count
        let initialAction = CloseDecision.action(
            bundleID: application.bundleIdentifier,
            applicationName: application.localizedName,
            isStandardWindow: true,
            standardWindowCount: standardWindowCount,
            rules: rules
        )
        guard initialAction == .quit,
              let visibleWindowCount = visibleWindowCount(for: application.processIdentifier),
              visibleWindowCount > 0 else { return Unmanaged.passUnretained(event) }

        keyboardRequestID &+= 1
        let requestID = keyboardRequestID
        logger.info("close candidate: source=keyboard kind=standard pid=\(application.processIdentifier, privacy: .public)")
        scheduleKeyboardCheck(for: application, requestID: requestID, attempt: 0, sawEmptyWindows: false)
        return Unmanaged.passUnretained(event)
    }

    private func scheduleKeyboardCheck(for application: NSRunningApplication, requestID: Int, attempt: Int, sawEmptyWindows: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            guard self.keyboardEnabled, self.keyboardEventTap != nil, self.keyboardRequestID == requestID else {
                self.logger.info("close check cancelled: source=keyboard reason=monitorChanged pid=\(application.processIdentifier, privacy: .public)")
                return
            }
            guard !application.isTerminated,
                  NSRunningApplication(processIdentifier: application.processIdentifier) == application else {
                self.logger.info("close check cancelled: source=keyboard reason=targetStopped pid=\(application.processIdentifier, privacy: .public)")
                return
            }
            guard CloseDecision.action(
                    bundleID: application.bundleIdentifier,
                    applicationName: application.localizedName,
                    isStandardWindow: true,
                    standardWindowCount: 1,
                    rules: self.rules
                  ) == .quit else {
                self.logger.info("close check cancelled: source=keyboard reason=ruleChanged pid=\(application.processIdentifier, privacy: .public)")
                return
            }

            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.15)
            var windowsValue: CFTypeRef?
            let axStatus = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
            guard axStatus == .success, let windows = windowsValue as? [AXUIElement] else {
                self.logger.info("close check unavailable: source=keyboard pid=\(application.processIdentifier, privacy: .public) attempt=\(attempt, privacy: .public) axStatus=\(axStatus.rawValue, privacy: .public)")
                if attempt < 7 {
                    self.scheduleKeyboardCheck(for: application, requestID: requestID, attempt: attempt + 1, sawEmptyWindows: false)
                }
                return
            }
            let visibleWindowCount = self.visibleWindowCount(for: application.processIdentifier)
            let noRemainingWindows = CloseDecision.shouldQuitAfterKeyboardClose(
                initialAction: .quit,
                remainingWindowCount: windows.count,
                remainingVisibleWindowCount: visibleWindowCount,
                targetStillRunning: true
            )
            self.logger.info("close check: source=keyboard pid=\(application.processIdentifier, privacy: .public) attempt=\(attempt, privacy: .public) ax=\(windows.count, privacy: .public) onscreen=\(visibleWindowCount ?? -1, privacy: .public) empty=\(noRemainingWindows, privacy: .public)")

            if noRemainingWindows && sawEmptyWindows {
                let requested = application.terminate()
                self.logger.info("quit requested: source=keyboard pid=\(application.processIdentifier, privacy: .public) accepted=\(requested, privacy: .public)")
            } else if attempt < 7, !(sawEmptyWindows && !noRemainingWindows) {
                self.scheduleKeyboardCheck(
                    for: application,
                    requestID: requestID,
                    attempt: attempt + 1,
                    sawEmptyWindows: noRemainingWindows
                )
            }
        }
    }

    private func scheduleFullScreenCheck(for application: NSRunningApplication, closingWindowID: UInt32, requestID: Int, attempt: Int, sawNoWindows: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.8 : 0.25)) { [weak self] in
            guard let self,
                  self.eventTap != nil,
                  self.fullScreenRequestID == requestID,
                  !application.isTerminated,
                  NSRunningApplication(processIdentifier: application.processIdentifier) == application,
                  CloseDecision.action(
                    bundleID: application.bundleIdentifier,
                    applicationName: application.localizedName,
                    isStandardWindow: true,
                    standardWindowCount: 1,
                    rules: self.rules
                  ) == .quit else { return }

            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.15)
            let windows: [AXUIElement]? = self.attribute(kAXWindowsAttribute, from: appElement)
            let standardWindowCount = windows?.filter {
                self.stringAttribute(kAXSubroleAttribute, from: $0) == kAXStandardWindowSubrole as String
            }.count
            let visibleWindowCount = self.visibleWindowCount(for: application.processIdentifier)
            let otherScreenSizedWindowCount = self.screenSizedWindowCount(for: application.processIdentifier, excluding: closingWindowID)
            let noWindows = CloseDecision.shouldQuitAfterFullScreenClose(
                remainingStandardWindowCount: standardWindowCount,
                remainingVisibleWindowCount: visibleWindowCount,
                remainingScreenSizedWindowCount: otherScreenSizedWindowCount
            )
            self.logger.info("close check: source=fullScreen pid=\(application.processIdentifier, privacy: .public) windowID=\(closingWindowID, privacy: .public) attempt=\(attempt, privacy: .public) ax=\(standardWindowCount ?? -1, privacy: .public) onscreen=\(visibleWindowCount ?? -1, privacy: .public) otherSpaces=\(otherScreenSizedWindowCount ?? -1, privacy: .public) empty=\(noWindows, privacy: .public)")
            if CloseDecision.shouldQuitAfterConfirmedFullScreenClose(previousSampleWasEmpty: sawNoWindows, currentSampleIsEmpty: noWindows) {
                let requested = application.terminate()
                self.logger.info("quit requested: source=fullScreen pid=\(application.processIdentifier, privacy: .public) accepted=\(requested, privacy: .public)")
            } else if attempt < 8 {
                self.scheduleFullScreenCheck(
                    for: application,
                    closingWindowID: closingWindowID,
                    requestID: requestID,
                    attempt: attempt + 1,
                    sawNoWindows: noWindows
                )
            }
        }
    }

    private func visibleWindowCount(for pid: pid_t) -> Int? {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        return windowInfo.filter {
            ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid)
                && ($0[kCGWindowLayer as String] as? Int) == 0
        }.count
    }

    private func screenSizedWindowID(for pid: pid_t) -> UInt32? {
        screenSizedWindows(for: pid, options: [.optionOnScreenOnly, .excludeDesktopElements])?
            .first?[kCGWindowNumber as String].flatMap { ($0 as? NSNumber)?.uint32Value }
    }

    private func screenSizedWindowCount(for pid: pid_t, excluding closingWindowID: UInt32) -> Int? {
        guard let windows = screenSizedWindows(for: pid, options: [.optionAll, .excludeDesktopElements]) else { return nil }
        let windowIDs = windows.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        guard windowIDs.count == windows.count else { return nil }
        return CloseDecision.otherWindowCount(windowIDs, excluding: closingWindowID)
    }

    private func screenSizedWindows(for pid: pid_t, options: CGWindowListOption) -> [[String: Any]]? {
        // A full-screen window in another Space may be absent from both AXWindows and the onscreen list.
        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let screenSizes = NSScreen.screens.map(\.frame.size)
        guard !screenSizes.isEmpty else { return nil }
        return windowInfo.filter {
            guard ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid),
                  ($0[kCGWindowLayer as String] as? Int) == 0,
                  ($0[kCGWindowAlpha as String] as? Double ?? 0) > 0,
                  let bounds = $0[kCGWindowBounds as String] as? [String: NSNumber],
                  let width = bounds["Width"], let height = bounds["Height"] else { return false }
            return CloseDecision.isScreenSizedWindow(
                CGSize(width: width.doubleValue, height: height.doubleValue),
                screenSizes: screenSizes
            )
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            pendingClose = nil
            pendingFullScreenClose = nil
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDragged, pendingFullScreenClose != nil {
            pendingFullScreenClose = nil
        }
        if type == .leftMouseDragged, pendingClose != nil {
            return nil
        }
        if type == .leftMouseUp, let pending = pendingFullScreenClose {
            pendingFullScreenClose = nil
            if let closingWindowID = pending.windowID {
                fullScreenRequestID &+= 1
                logger.info("close candidate: source=redButton kind=fullScreen pid=\(pending.application.processIdentifier, privacy: .public) windowID=\(closingWindowID, privacy: .public)")
                scheduleFullScreenCheck(for: pending.application, closingWindowID: closingWindowID, requestID: fullScreenRequestID, attempt: 0, sawNoWindows: false)
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseUp, let pending = pendingClose {
            pendingClose = nil
            if let released = targetForCloseButton(at: event.location),
               pending.application == released.application,
               CFEqual(pending.closeButton, released.closeButton),
               CloseDecision.action(
                bundleID: released.application.bundleIdentifier,
                applicationName: released.application.localizedName,
                isStandardWindow: released.isStandardWindow,
                standardWindowCount: released.standardWindowCount,
                rules: rules
               ) == .quit {
                requestQuit(pending)
            }
            return nil
        }
        guard type == .leftMouseDown,
              let target = targetForCloseButton(at: event.location) else {
            return Unmanaged.passUnretained(event)
        }
        if target.isFullScreen {
            guard CloseDecision.shouldMonitorFullScreenClose(
                bundleID: target.application.bundleIdentifier,
                applicationName: target.application.localizedName,
                isStandardWindow: target.isStandardWindow,
                rules: rules
            ) else { return Unmanaged.passUnretained(event) }
            pendingFullScreenClose = target
            return Unmanaged.passUnretained(event)
        }
        guard CloseDecision.action(
            bundleID: target.application.bundleIdentifier,
            applicationName: target.application.localizedName,
            isStandardWindow: target.isStandardWindow,
            standardWindowCount: target.standardWindowCount,
            rules: rules
        ) == .quit else {
            return Unmanaged.passUnretained(event)
        }

        pendingClose = target
        return nil
    }

    private func requestQuit(_ target: Target) {
        DispatchQueue.main.async { [self] in
            guard !target.application.isTerminated else { return }
            let requested = target.application.terminate()
            logger.info("quit requested: source=redButton kind=standard pid=\(target.application.processIdentifier, privacy: .public) accepted=\(requested, privacy: .public)")
            if !requested {
                AXUIElementPerformAction(target.closeButton, kAXPressAction as CFString)
            }
        }
    }

    private struct Target {
        let application: NSRunningApplication
        let closeButton: AXUIElement
        let isStandardWindow: Bool
        let isFullScreen: Bool
        let windowID: UInt32?
        let standardWindowCount: Int?
    }

    private func targetForCloseButton(at point: CGPoint) -> Target? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var hitValue: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hitValue) == .success,
              let hit = hitValue else { return nil }
        AXUIElementSetMessagingTimeout(hit, 0.15)

        var current = hit
        var window: AXUIElement?
        var ancestors: [AXUIElement] = []
        for _ in 0..<10 {
            ancestors.append(current)
            if stringAttribute(kAXRoleAttribute, from: current) == kAXWindowRole as String {
                window = current
                break
            }
            guard let parent: AXUIElement = attribute(kAXParentAttribute, from: current) else { break }
            current = parent
        }
        guard let window,
              let closeButton: AXUIElement = attribute(kAXCloseButtonAttribute, from: window),
              ancestors.contains(where: { CFEqual($0, closeButton) }) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.15)

        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              let application = NSRunningApplication(processIdentifier: pid),
              application != NSRunningApplication.current else { return nil }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.15)
        let windows: [AXUIElement]? = attribute(kAXWindowsAttribute, from: appElement)
        let count = windows?.filter { stringAttribute(kAXSubroleAttribute, from: $0) == kAXStandardWindowSubrole as String }.count
        let isFullScreen = attribute("AXFullScreen", from: window) as Bool? == true
        return Target(
            application: application,
            closeButton: closeButton,
            isStandardWindow: stringAttribute(kAXSubroleAttribute, from: window) == kAXStandardWindowSubrole as String,
            isFullScreen: isFullScreen,
            windowID: isFullScreen ? screenSizedWindowID(for: pid) : nil,
            standardWindowCount: count
        )
    }

    private func attribute<T>(_ name: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private func stringAttribute(_ name: String, from element: AXUIElement) -> String? {
        attribute(name, from: element)
    }
}
