import Foundation

let exceptions: Set<AppRule> = [
    AppRule(match: .bundleID, value: "com.example.music"),
    AppRule(match: .applicationName, value: "Legacy Helper")
]

func check(_ actual: CloseDecision.Action, _ expected: CloseDecision.Action, _ caseName: String) {
    precondition(actual == expected, "\(caseName): expected \(expected), got \(actual)")
}

check(CloseDecision.action(bundleID: "com.example.editor", applicationName: "Editor", isStandardWindow: true, standardWindowCount: 1, rules: exceptions), .quit, "last standard window")
check(CloseDecision.action(bundleID: "com.example.editor", applicationName: "Editor", isStandardWindow: true, standardWindowCount: 2, rules: exceptions), .close, "multiple windows")
check(CloseDecision.action(bundleID: "com.example.editor", applicationName: "Editor", isStandardWindow: false, standardWindowCount: 1, rules: exceptions), .close, "settings window")
check(CloseDecision.action(bundleID: "com.example.music", applicationName: "Music", isStandardWindow: true, standardWindowCount: 1, rules: exceptions), .close, "bundle ID exception")
check(CloseDecision.action(bundleID: "com.example.helper", applicationName: "Legacy Helper", isStandardWindow: true, standardWindowCount: 1, rules: exceptions), .close, "name exception")
check(CloseDecision.action(bundleID: "com.example.editor", applicationName: "Editor", isStandardWindow: true, standardWindowCount: nil, rules: exceptions), .close, "unavailable window count")
check(CloseDecision.action(bundleID: nil, applicationName: nil, isStandardWindow: true, standardWindowCount: 1, rules: exceptions), .close, "unknown application")
precondition(CloseDecision.shouldMonitorFullScreenClose(bundleID: "com.example.editor", applicationName: "Editor", isStandardWindow: true, rules: exceptions), "full-screen close is monitored before window count reaches one")
precondition(!CloseDecision.shouldMonitorFullScreenClose(bundleID: "com.example.music", applicationName: "Music", isStandardWindow: true, rules: exceptions), "excepted full-screen app is not monitored")
precondition(!CloseDecision.shouldMonitorFullScreenClose(bundleID: "com.example.editor", applicationName: "Editor", isStandardWindow: false, rules: exceptions), "nonstandard full-screen window is not monitored")
precondition(CloseDecision.isScreenSizedWindow(CGSize(width: 1800, height: 1130), screenSizes: [CGSize(width: 1800, height: 1169)]), "Windows App Beta full-screen window")
precondition(!CloseDecision.isScreenSizedWindow(CGSize(width: 1800, height: 1076), screenSizes: [CGSize(width: 1800, height: 1169)]), "Windows App Beta window after closing full screen")
precondition(!CloseDecision.isScreenSizedWindow(CGSize(width: 1800, height: 39), screenSizes: [CGSize(width: 1800, height: 1169)]), "menu bar strip is not a full-screen window")
precondition(!CloseDecision.isScreenSizedWindow(CGSize(width: 584, height: 520), screenSizes: [CGSize(width: 1800, height: 1169)]), "small auxiliary window is not a full-screen window")
precondition(CloseDecision.otherWindowCount([6157], excluding: 6157) == 0, "closed window is excluded even if it remains in Core Graphics")
precondition(CloseDecision.otherWindowCount([6039, 5892], excluding: 5892) == 1, "another full-screen window remains in a different Space")
precondition(CloseDecision.otherWindowCount([6157], excluding: nil) == nil, "unknown closing window is inconclusive")
precondition(CloseDecision.shouldQuitAfterFullScreenClose(remainingStandardWindowCount: 0, remainingVisibleWindowCount: 0, remainingScreenSizedWindowCount: 0), "full-screen window closed with no remaining windows")
precondition(!CloseDecision.shouldQuitAfterFullScreenClose(remainingStandardWindowCount: 0, remainingVisibleWindowCount: 0, remainingScreenSizedWindowCount: 1), "full-screen window remains in another Space")
precondition(!CloseDecision.shouldQuitAfterFullScreenClose(remainingStandardWindowCount: 1, remainingVisibleWindowCount: 1, remainingScreenSizedWindowCount: 1), "normal window remains after full-screen close")
precondition(!CloseDecision.shouldQuitAfterFullScreenClose(remainingStandardWindowCount: 0, remainingVisibleWindowCount: 1, remainingScreenSizedWindowCount: 0), "visible window remains after full-screen close")
precondition(!CloseDecision.shouldQuitAfterFullScreenClose(remainingStandardWindowCount: nil, remainingVisibleWindowCount: 0, remainingScreenSizedWindowCount: 0), "unavailable accessibility window count")
precondition(!CloseDecision.shouldQuitAfterFullScreenClose(remainingStandardWindowCount: 0, remainingVisibleWindowCount: 0, remainingScreenSizedWindowCount: nil), "unavailable cross-Space window count")
precondition(!CloseDecision.shouldQuitAfterConfirmedFullScreenClose(previousSampleWasEmpty: false, currentSampleIsEmpty: true), "one empty sample does not quit")
precondition(CloseDecision.shouldQuitAfterConfirmedFullScreenClose(previousSampleWasEmpty: true, currentSampleIsEmpty: true), "two consecutive empty samples quit")
precondition(!CloseDecision.shouldQuitAfterConfirmedFullScreenClose(previousSampleWasEmpty: true, currentSampleIsEmpty: false), "a window reappearing cancels confirmation")
precondition(CloseDecision.otherWindowCount([6039, 5892], excluding: 6039) == 1, "either interleaved full-screen window can be closed first")
precondition(CloseDecision.otherWindowCount([6157, 6039], excluding: 6157) == 1, "a lingering clicked window does not hide another Space")
precondition(CloseDecision.shouldQuitAfterKeyboardClose(initialAction: .quit, remainingWindowCount: 0, remainingVisibleWindowCount: 0, targetStillRunning: true), "last window closed")
precondition(CloseDecision.shouldQuitAfterKeyboardClose(initialAction: .quit, remainingWindowCount: 1, remainingVisibleWindowCount: 0, targetStillRunning: true), "hidden window remains in accessibility list")
precondition(!CloseDecision.shouldQuitAfterKeyboardClose(initialAction: .quit, remainingWindowCount: 1, remainingVisibleWindowCount: 1, targetStillRunning: true), "tab or save dialog remains")
precondition(!CloseDecision.shouldQuitAfterKeyboardClose(initialAction: .quit, remainingWindowCount: 1, remainingVisibleWindowCount: nil, targetStillRunning: true), "unavailable visible window state")
precondition(!CloseDecision.shouldQuitAfterKeyboardClose(initialAction: .quit, remainingWindowCount: nil, remainingVisibleWindowCount: nil, targetStillRunning: true), "unavailable window state")
precondition(!CloseDecision.shouldQuitAfterKeyboardClose(initialAction: .quit, remainingWindowCount: nil, remainingVisibleWindowCount: 0, targetStillRunning: true), "unavailable AX state cannot prove keyboard close")
precondition(!CloseDecision.shouldQuitAfterKeyboardClose(initialAction: .quit, remainingWindowCount: 0, remainingVisibleWindowCount: 0, targetStillRunning: false), "app already exited")
precondition(!CloseDecision.shouldQuitAfterKeyboardClose(initialAction: .close, remainingWindowCount: 0, remainingVisibleWindowCount: 0, targetStillRunning: true), "excepted app")

print("36 decision cases passed")
