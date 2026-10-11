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
precondition(CloseDecision.shouldQuitAfterKeyboardClose(initialAction: .quit, remainingWindowCount: 0, remainingVisibleWindowCount: 0, targetStillRunning: true), "last window closed")
precondition(CloseDecision.shouldQuitAfterKeyboardClose(initialAction: .quit, remainingWindowCount: 1, remainingVisibleWindowCount: 0, targetStillRunning: true), "hidden window remains in accessibility list")
precondition(!CloseDecision.shouldQuitAfterKeyboardClose(initialAction: .quit, remainingWindowCount: 1, remainingVisibleWindowCount: 1, targetStillRunning: true), "tab or save dialog remains")
precondition(!CloseDecision.shouldQuitAfterKeyboardClose(initialAction: .quit, remainingWindowCount: 1, remainingVisibleWindowCount: nil, targetStillRunning: true), "unavailable visible window state")
precondition(!CloseDecision.shouldQuitAfterKeyboardClose(initialAction: .quit, remainingWindowCount: nil, remainingVisibleWindowCount: nil, targetStillRunning: true), "unavailable window state")
precondition(!CloseDecision.shouldQuitAfterKeyboardClose(initialAction: .quit, remainingWindowCount: 0, remainingVisibleWindowCount: 0, targetStillRunning: false), "app already exited")
precondition(!CloseDecision.shouldQuitAfterKeyboardClose(initialAction: .close, remainingWindowCount: 0, remainingVisibleWindowCount: 0, targetStillRunning: true), "excepted app")

print("14 decision cases passed")
