import Foundation

let exceptions: Set<AppRule> = [
    AppRule(match: .bundleID, value: "com.example.music"),
    AppRule(match: .applicationName, value: "Legacy Helper")
]
let excludePolicy = RulePolicy(mode: .allExceptListed, rules: exceptions)
let onlyPolicy = RulePolicy(mode: .onlyListed, rules: exceptions)

func check(_ actual: CloseDecision.Action, _ expected: CloseDecision.Action, _ caseName: String) {
    precondition(actual == expected, "\(caseName): expected \(expected), got \(actual)")
}

check(CloseDecision.action(bundleID: "com.example.editor", applicationName: "Editor", isStandardWindow: true, standardWindowCount: 1, policy: excludePolicy), .quit, "last standard window")
check(CloseDecision.action(bundleID: "com.example.editor", applicationName: "Editor", isStandardWindow: true, standardWindowCount: 2, policy: excludePolicy), .close, "multiple windows")
check(CloseDecision.action(bundleID: "com.example.editor", applicationName: "Editor", isStandardWindow: false, standardWindowCount: 1, policy: excludePolicy), .close, "settings window")
check(CloseDecision.action(bundleID: "com.example.music", applicationName: "Music", isStandardWindow: true, standardWindowCount: 1, policy: excludePolicy), .close, "bundle ID exception")
check(CloseDecision.action(bundleID: "com.example.helper", applicationName: "Legacy Helper", isStandardWindow: true, standardWindowCount: 1, policy: excludePolicy), .close, "name exception")
check(CloseDecision.action(bundleID: "com.example.editor", applicationName: "Editor", isStandardWindow: true, standardWindowCount: nil, policy: excludePolicy), .close, "unavailable window count")
check(CloseDecision.action(bundleID: nil, applicationName: nil, isStandardWindow: true, standardWindowCount: 1, policy: excludePolicy), .close, "unknown application")
precondition(CloseDecision.shouldMonitorFullScreenClose(bundleID: "com.example.editor", applicationName: "Editor", isStandardWindow: true, policy: excludePolicy), "full-screen close is monitored before window count reaches one")
precondition(!CloseDecision.shouldMonitorFullScreenClose(bundleID: "com.example.music", applicationName: "Music", isStandardWindow: true, policy: excludePolicy), "excepted full-screen app is not monitored")
precondition(!CloseDecision.shouldMonitorFullScreenClose(bundleID: "com.example.editor", applicationName: "Editor", isStandardWindow: false, policy: excludePolicy), "nonstandard full-screen window is not monitored")
check(CloseDecision.action(bundleID: "com.example.music", applicationName: "Music", isStandardWindow: true, standardWindowCount: 1, policy: onlyPolicy), .quit, "only listed bundle ID quits")
check(CloseDecision.action(bundleID: "com.example.editor", applicationName: "Editor", isStandardWindow: true, standardWindowCount: 1, policy: onlyPolicy), .close, "unlisted app is not managed in only mode")
check(CloseDecision.action(bundleID: "com.example.music", applicationName: "Music", isStandardWindow: true, standardWindowCount: 2, policy: onlyPolicy), .close, "only listed app with multiple windows")
check(CloseDecision.action(bundleID: nil, applicationName: nil, isStandardWindow: true, standardWindowCount: 1, policy: onlyPolicy), .close, "unknown app is not managed in only mode")
precondition(CloseDecision.shouldMonitorFullScreenClose(bundleID: "com.example.music", applicationName: "Music", isStandardWindow: true, policy: onlyPolicy), "listed full-screen app is monitored in only mode")
precondition(!CloseDecision.shouldMonitorFullScreenClose(bundleID: "com.example.editor", applicationName: "Editor", isStandardWindow: true, policy: onlyPolicy), "unlisted full-screen app is not monitored in only mode")
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
precondition(AppRule(match: .applicationName, value: "Legacy Helper").matches(searchQuery: "  helper "), "search trims whitespace and ignores case")
precondition(AppRule(match: .bundleID, value: "com.example.music").matches(searchQuery: "example"), "search matches bundle ID")
precondition(!AppRule(match: .applicationName, value: "Music").matches(searchQuery: "editor"), "search excludes non-matching app")
precondition(AppRule(match: .applicationName, value: "Music").matches(searchQuery: "   "), "blank search matches every app")

print("46 decision cases passed")

MainActor.assumeIsolated {
    let name = "fun.bgm.neatquit.onboarding-tests.\(UUID().uuidString)"
    let prefs = UserDefaults(suiteName: name)!
    defer { prefs.removePersistentDomain(forName: name) }
    let fresh = RuleStore(defaults: prefs)
    precondition(fresh.needsOnboarding)
    precondition(!prefs.bool(forKey: "rules.legacyUsageSnapshot"))
    precondition(fresh.exceptionRules.contains(AppRule(match: .bundleID, value: "com.apple.Terminal")))
    precondition(RuleStore(defaults: prefs).needsOnboarding)
    fresh.finishOnboarding()
    precondition(!RuleStore(defaults: prefs).needsOnboarding)
    prefs.removePersistentDomain(forName: name)
    prefs.set(false, forKey: "enabled")
    let old = RuleStore(defaults: prefs)
    precondition(!old.needsOnboarding && old.exceptionRules == RuleStore.legacyDefaults)
    prefs.removePersistentDomain(forName: name)
    prefs.set(Data("broken".utf8), forKey: "applicationRules")
    precondition(RuleStore(defaults: prefs).exceptionRules == RuleStore.legacyDefaults)
    prefs.removePersistentDomain(forName: name)
    prefs.set(try! JSONEncoder().encode(Set<AppRule>()), forKey: "applicationRules")
    prefs.set("onlyListed", forKey: "ruleMode")
    let custom = RuleStore(defaults: prefs)
    precondition(custom.mode == .onlyListed && custom.exceptionRules.isEmpty)
}
print("Onboarding migration cases passed")

let scheduleNow = Date(timeIntervalSince1970: 1_700_000_000)
let sampleAction = ScheduledAction(
    target: .application("com.example.timer"),
    displayName: "Timer",
    fireAt: scheduleNow.addingTimeInterval(1781)
)
precondition(
    (try! JSONDecoder().decode(ScheduledAction.self, from: JSONEncoder().encode(sampleAction))) == sampleAction,
    "scheduled action codable round trip"
)

precondition(ScheduleDecision.remainingText(fireAt: scheduleNow.addingTimeInterval(1781), now: scheduleNow) == "29:41", "29:41 formatting")
precondition(ScheduleDecision.remainingText(fireAt: scheduleNow.addingTimeInterval(4320), now: scheduleNow) == "1:12:00", "hour formatting")
precondition(ScheduleDecision.remainingText(fireAt: scheduleNow.addingTimeInterval(5), now: scheduleNow) == "0:05", "sub-minute formatting")
precondition(ScheduleDecision.remainingText(fireAt: scheduleNow.addingTimeInterval(-10), now: scheduleNow) == "0:00", "overdue formatting")
precondition(ScheduleDecision.remainingText(fireAt: scheduleNow.addingTimeInterval(3600), now: scheduleNow) == "1:00:00", "exact hour formatting")

precondition(ScheduleDecision.outcome(fireAt: scheduleNow, now: scheduleNow) == .fire, "exact fire time")
precondition(ScheduleDecision.outcome(fireAt: scheduleNow, now: scheduleNow.addingTimeInterval(-1)) == .waiting, "before fire time")
precondition(ScheduleDecision.outcome(fireAt: scheduleNow, now: scheduleNow.addingTimeInterval(299)) == .fire, "299 seconds overdue still fires")
precondition(ScheduleDecision.outcome(fireAt: scheduleNow, now: scheduleNow.addingTimeInterval(300)) == .fire, "300 seconds overdue still fires")
precondition(ScheduleDecision.outcome(fireAt: scheduleNow, now: scheduleNow.addingTimeInterval(301)) == .expired, "301 seconds overdue expires")
precondition(ScheduleDecision.isDue(fireAt: scheduleNow, now: scheduleNow.addingTimeInterval(299)), "isDue inside window")
precondition(ScheduleDecision.isStale(fireAt: scheduleNow, now: scheduleNow.addingTimeInterval(301)), "isStale past window")

let earlyApp = ScheduledAction(target: .application("com.example.early"), displayName: "Early", fireAt: scheduleNow.addingTimeInterval(60))
let lateApp = ScheduledAction(target: .application("com.example.late"), displayName: "Late", fireAt: scheduleNow.addingTimeInterval(600))
let diskAction = ScheduledAction(target: .disk(mainVolumePath: "/Volumes/Disk", bsdName: "disk9"), displayName: "Disk", fireAt: scheduleNow.addingTimeInterval(30))
precondition(ScheduleDecision.topLevelSuffix([], kind: .application, now: scheduleNow) == nil, "no actions yields no suffix")
precondition(ScheduleDecision.topLevelSuffix([lateApp, earlyApp], kind: .application, now: scheduleNow) == "1:00", "app entry shows earliest app action")
precondition(ScheduleDecision.topLevelSuffix([lateApp, diskAction], kind: .application, now: scheduleNow) == "10:00", "app entry ignores disk actions")
precondition(ScheduleDecision.topLevelSuffix([lateApp, diskAction], kind: .disk, now: scheduleNow) == "0:30", "disk entry ignores app actions")
precondition(ScheduleDecision.ordered([lateApp, earlyApp]).map(\.displayName) == ["Early", "Late"], "actions ordered by fire time")
let sameTimeB = ScheduledAction(target: .application("com.example.b"), displayName: "B", fireAt: scheduleNow)
let sameTimeA = ScheduledAction(target: .application("com.example.a"), displayName: "A", fireAt: scheduleNow)
precondition(ScheduleDecision.ordered([sameTimeB, sameTimeA]).map(\.displayName) == ["A", "B"], "ties ordered by name")

// 磁盘命名：主卷选择与回退链
let smallVolume = DiskVolumeInfo(path: "/Volumes/EFI", name: "VTOYEFI", capacity: 33_000_000, isBrowsable: true, isReadOnly: false)
let bigVolume = DiskVolumeInfo(path: "/Volumes/Ventoy", name: "Ventoy", capacity: 15_000_000_000, isBrowsable: true, isReadOnly: false)
let hiddenVolume = DiskVolumeInfo(path: "/Volumes/Hidden", name: "Huge", capacity: 90_000_000_000, isBrowsable: false, isReadOnly: false)
let readOnlyVolume = DiskVolumeInfo(path: "/Volumes/RO", name: "ReadOnly", capacity: 80_000_000_000, isBrowsable: true, isReadOnly: true)
precondition(DiskNaming.mainVolume(in: [smallVolume, bigVolume])?.name == "Ventoy", "main volume is the largest browsable volume")
precondition(DiskNaming.mainVolume(in: [hiddenVolume, readOnlyVolume, smallVolume])?.name == "VTOYEFI", "non-browsable and read-only volumes are skipped")
precondition(DiskNaming.displayName(volumes: [smallVolume, bigVolume], mediaName: "SanDisk Ultra USB 3.0 Media", vendor: "SanDisk", model: "Ultra USB 3.0") == "Ventoy", "volume name wins")
precondition(DiskNaming.displayName(volumes: [], mediaName: "SanDisk Ultra USB 3.0 Media", vendor: "SanDisk", model: "Ultra USB 3.0") == "SanDisk Ultra USB 3.0", "media name fallback trims suffix")
precondition(DiskNaming.displayName(volumes: [], mediaName: nil, vendor: "SanDisk", model: "Ultra USB 3.0") == "SanDisk Ultra USB 3.0", "vendor and model fallback")
precondition(DiskNaming.detail(vendor: "SanDisk", model: "Ultra USB 3.0", capacity: 15_000_000_000).contains("SanDisk"), "detail includes vendor")

precondition(DiskAccess.requestAccess(to: NSTemporaryDirectory()), "temporary directory is readable")
precondition(
    !DiskAccess.requestAccess(to: "/nonexistent-\(UUID().uuidString)"),
    "missing path is not readable"
)

print("Schedule decision cases passed")

MainActor.assumeIsolated {
    let name = "fun.bgm.neatquit.schedule-tests.\(UUID().uuidString)"
    let prefs = UserDefaults(suiteName: name)!
    defer { prefs.removePersistentDomain(forName: name) }

    let store = ScheduledActionStore(defaults: prefs)
    precondition(store.actions.isEmpty)
    store.add(target: .application("com.example.a"), displayName: "A", duration: 1800, now: scheduleNow)
    precondition(store.actions.count == 1)
    precondition(store.actions[0].fireAt == scheduleNow.addingTimeInterval(1800))
    precondition(ScheduledActionStore(defaults: prefs).actions.count == 1, "armed action persisted")

    store.add(target: .application("com.example.a"), displayName: "A", duration: 60, now: scheduleNow)
    precondition(store.actions.count == 1, "same target replaces instead of appending")
    precondition(store.actions[0].fireAt == scheduleNow.addingTimeInterval(60))

    store.add(target: .disk(mainVolumePath: "/Volumes/Ventoy", bsdName: "disk4"), displayName: "Ventoy", duration: 120, now: scheduleNow)
    precondition(store.actions.count == 2, "app and disk actions coexist")
    precondition(ScheduledActionStore(defaults: prefs).actions.count == 2, "disk action persisted")

    let firingID = store.actions[0].id
    store.markFiring(id: firingID)
    precondition(ScheduledActionStore(defaults: prefs).actions.count == 1, "firing entries are not persisted")
    store.markRefused(id: firingID)
    precondition(store.actions.first(where: { $0.id == firingID })?.state == .refused)

    store.cancelAll()
    precondition(store.actions.isEmpty && ScheduledActionStore(defaults: prefs).actions.isEmpty)

    // 旧键迁移
    prefs.removePersistentDomain(forName: name)
    let legacy = [[
        "id": UUID().uuidString,
        "bundleID": "com.example.legacy",
        "displayName": "Legacy",
        "fireAt": scheduleNow.addingTimeInterval(300).timeIntervalSinceReferenceDate,
        "state": "armed",
    ]]
    prefs.set(try! JSONSerialization.data(withJSONObject: legacy), forKey: "schedule.timers")
    let migrated = ScheduledActionStore(defaults: prefs)
    precondition(migrated.actions.count == 1)
    precondition(migrated.actions[0].target.bundleID == "com.example.legacy")
    precondition(prefs.data(forKey: "schedule.actions") != nil, "legacy key migrated")
    precondition(prefs.data(forKey: "schedule.timers") == nil, "legacy key removed")

    prefs.removePersistentDomain(forName: name)
    prefs.set(Data("broken".utf8), forKey: "schedule.actions")
    precondition(ScheduledActionStore(defaults: prefs).actions.isEmpty, "corrupt data does not block startup")

    // 调度器：注入固定时钟与桩函数
    prefs.removePersistentDomain(forName: name)
    let schedStore = ScheduledActionStore(defaults: prefs)
    var clock = scheduleNow
    var available = true
    var stillPresent = true
    var performCalls = 0
    let scheduler = ScheduledActionScheduler(
        store: schedStore,
        now: { clock },
        isAvailable: { _ in available },
        isStillPresent: { _ in stillPresent },
        perform: { _, completion in performCalls += 1; completion(true) }
    )

    scheduler.add(target: .application("com.example.c"), displayName: "C", duration: 60)
    scheduler.tick()
    precondition(performCalls == 0 && schedStore.actions.first?.state == .armed, "waiting before fire time")

    clock = scheduleNow.addingTimeInterval(61)
    scheduler.tick()
    precondition(performCalls == 1 && schedStore.actions.first?.state == .firing, "fires when due")

    clock = clock.addingTimeInterval(ScheduleDecision.verificationDelay)
    stillPresent = false
    scheduler.tick()
    precondition(schedStore.actions.isEmpty, "completed action removes the timer")

    // 过期丢弃
    available = true
    stillPresent = true
    scheduler.add(target: .application("com.example.d"), displayName: "D", duration: 60)
    clock = clock.addingTimeInterval(60 + 301)
    scheduler.tick()
    precondition(schedStore.actions.isEmpty && performCalls == 1, "expired action is dropped without performing")

    // 被拒与重试
    scheduler.add(target: .disk(mainVolumePath: "/Volumes/X", bsdName: "disk7"), displayName: "X", duration: 10)
    clock = clock.addingTimeInterval(10)
    scheduler.tick()
    clock = clock.addingTimeInterval(ScheduleDecision.verificationDelay)
    scheduler.tick()
    precondition(schedStore.actions.first?.state == .refused, "refused state after failed verification")
    let refusedID = schedStore.actions[0].id
    scheduler.retry(id: refusedID)
    precondition(performCalls == 3, "retry issues another perform request")

    // 目标提前消失
    schedStore.cancelAll()
    available = false
    scheduler.add(target: .disk(mainVolumePath: "/Volumes/Gone", bsdName: "disk8"), displayName: "Gone", duration: 600)
    scheduler.tick()
    precondition(schedStore.actions.isEmpty && performCalls == 3, "missing target removes the timer")

    // 未弹出目标消失后自动移除
    available = true
    stillPresent = true
    scheduler.add(target: .disk(mainVolumePath: "/Volumes/Refused", bsdName: "disk9"), displayName: "Refused", duration: 10)
    clock = clock.addingTimeInterval(10)
    scheduler.tick()
    clock = clock.addingTimeInterval(ScheduleDecision.verificationDelay)
    scheduler.tick()
    precondition(schedStore.actions.first?.state == .refused, "refused before target disappears")
    stillPresent = false
    clock = clock.addingTimeInterval(2)
    scheduler.tick()
    precondition(schedStore.actions.isEmpty, "refused action is removed after its target disappears")

    prefs.removePersistentDomain(forName: name)
}
print("Schedule store and scheduler cases passed")

MainActor.assumeIsolated {
    let name = "fun.bgm.neatquit.idle-tests.\(UUID().uuidString)"
    let prefs = UserDefaults(suiteName: name)!
    defer { prefs.removePersistentDomain(forName: name) }

    let idleTarget = ScheduleTarget.disk(mainVolumePath: "/Volumes/Ventoy", bsdName: "disk4")

    // 解码：新记录保留方式，旧记录按倒计时读取
    let idleSample = ScheduledAction(
        target: idleTarget,
        displayName: "Ventoy",
        fireAt: scheduleNow.addingTimeInterval(600),
        mode: .idle,
        idleSeconds: 600
    )
    let roundTrip = try! JSONDecoder().decode(
        ScheduledAction.self,
        from: try! JSONEncoder().encode(idleSample)
    )
    precondition(roundTrip.mode == .idle && roundTrip.idleSeconds == 600, "idle fields round trip")
    precondition(roundTrip.fireAt == idleSample.fireAt, "fireAt round trip")

    let legacyJSON: [String: Any] = [
        "id": UUID().uuidString,
        "target": ["kind": "disk", "identifier": "/Volumes/Legacy"],
        "displayName": "Legacy",
        "fireAt": scheduleNow.timeIntervalSinceReferenceDate,
        "state": "armed",
    ]
    let legacy = try! JSONDecoder().decode(
        ScheduledAction.self,
        from: try! JSONSerialization.data(withJSONObject: legacyJSON)
    )
    precondition(legacy.mode == .timed && legacy.idleSeconds == nil, "legacy record defaults to timed")

    // 判定：闲置没有过期窗口
    precondition(ScheduleDecision.outcome(for: idleSample, now: scheduleNow) == .waiting, "idle waits before threshold")
    precondition(
        ScheduleDecision.outcome(for: idleSample, now: scheduleNow.addingTimeInterval(600)) == .fire,
        "idle fires at threshold"
    )
    precondition(
        ScheduleDecision.outcome(for: idleSample, now: scheduleNow.addingTimeInterval(36_000)) == .fire,
        "idle never expires"
    )

    // 存储：方式互斥、覆盖、运行时刷新不落盘
    let store = ScheduledActionStore(defaults: prefs)
    store.add(target: idleTarget, displayName: "Ventoy", duration: 600, now: scheduleNow, mode: .idle)
    precondition(store.actions.count == 1)
    precondition(store.actions[0].mode == .idle && store.actions[0].idleSeconds == 600)
    precondition(store.actions[0].fireAt == scheduleNow.addingTimeInterval(600))

    store.add(target: idleTarget, displayName: "Ventoy", duration: 60, now: scheduleNow, mode: .timed)
    precondition(store.actions.count == 1, "switching mode replaces the rule")
    precondition(store.actions[0].mode == .timed && store.actions[0].idleSeconds == nil)

    store.add(target: idleTarget, displayName: "Ventoy", duration: 600, now: scheduleNow, mode: .idle)
    let idleID = store.actions[0].id
    store.resetIdleStart(id: idleID, seconds: 600, now: scheduleNow.addingTimeInterval(300))
    precondition(store.actions[0].fireAt == scheduleNow.addingTimeInterval(900))
    let reloaded = ScheduledActionStore(defaults: prefs)
    precondition(
        reloaded.actions[0].fireAt == scheduleNow.addingTimeInterval(600),
        "runtime idle reset is not persisted"
    )

    // 调度器：活动重置、到点触发、失败顺延、连续失败上限
    prefs.removePersistentDomain(forName: name)
    let schedStore = ScheduledActionStore(defaults: prefs)
    var clock = scheduleNow
    var active = false
    var present = true
    var accepted = false
    var performs = 0
    let scheduler = ScheduledActionScheduler(
        store: schedStore,
        now: { clock },
        isAvailable: { _ in true },
        isStillPresent: { _ in present },
        perform: { _, completion in performs += 1; completion(accepted) },
        isActive: { _ in active }
    )
    scheduler.add(target: idleTarget, displayName: "Ventoy", duration: 600, mode: .idle)
    precondition(schedStore.actions[0].fireAt == scheduleNow.addingTimeInterval(600), "idle starts at creation")

    // 用小步长推进，避免触发「长间隔 = 唤醒」的重置逻辑。
    @MainActor func advance(_ seconds: TimeInterval) {
        var remaining = seconds
        while remaining > 0 {
            let delta = min(remaining, 30)
            clock = clock.addingTimeInterval(delta)
            scheduler.tick()
            remaining -= delta
        }
    }

    active = true
    advance(100)
    precondition(schedStore.actions[0].fireAt == clock.addingTimeInterval(600), "activity resets idle start")
    precondition(performs == 0, "activity never fires")

    active = false
    advance(600)
    precondition(performs == 1, "idle fires after threshold")
    precondition(schedStore.actions[0].state == .armed, "idle failure defers instead of refusing")
    precondition(schedStore.actions[0].fireAt == clock.addingTimeInterval(600), "deferral restarts the threshold")
    precondition(
        ScheduledActionStore(defaults: prefs).actions.count == 1,
        "deferral re-persists the idle rule after firing"
    )

    advance(600)
    precondition(schedStore.actions[0].state == .armed, "second failure still defers")

    // 检测到读写把连续失败计数清零
    active = true
    advance(10)
    active = false
    precondition(schedStore.actions[0].state == .armed)

    advance(600)
    precondition(schedStore.actions[0].state == .armed, "activity reset the failure counter")
    advance(600)
    precondition(schedStore.actions[0].state == .armed, "second failure after reset")
    advance(600)
    precondition(schedStore.actions[0].state == .refused, "third consecutive failure refuses")

    // 手动重试 + 成功复查
    accepted = true
    scheduler.retry(id: schedStore.actions[0].id)
    precondition(schedStore.actions[0].state == .firing, "retry issues a perform request")
    clock = clock.addingTimeInterval(ScheduleDecision.verificationDelay)
    present = false
    scheduler.tick()
    precondition(schedStore.actions.isEmpty, "successful retry removes the rule")

    // 启动时重置闲置起点
    prefs.removePersistentDomain(forName: name)
    let launchStore = ScheduledActionStore(defaults: prefs)
    launchStore.add(target: idleTarget, displayName: "Ventoy", duration: 600, now: scheduleNow, mode: .idle)
    let launchScheduler = ScheduledActionScheduler(
        store: launchStore,
        now: { scheduleNow.addingTimeInterval(3600) },
        isAvailable: { _ in true },
        isStillPresent: { _ in true },
        perform: { _, completion in completion(false) },
        isActive: { _ in false }
    )
    precondition(
        launchStore.actions[0].fireAt == scheduleNow.addingTimeInterval(3600 + 600),
        "scheduler resets idle start on launch"
    )
    _ = launchScheduler

    // 长 tick 间隔（睡眠唤醒）重置
    prefs.removePersistentDomain(forName: name)
    var wakeClock = scheduleNow
    let wakeStore = ScheduledActionStore(defaults: prefs)
    let wakeScheduler = ScheduledActionScheduler(
        store: wakeStore,
        now: { wakeClock },
        isAvailable: { _ in true },
        isStillPresent: { _ in true },
        perform: { _, completion in completion(false) },
        isActive: { _ in false }
    )
    wakeScheduler.add(target: idleTarget, displayName: "Ventoy", duration: 600, mode: .idle)
    wakeScheduler.tick()
    wakeClock = scheduleNow.addingTimeInterval(7200)
    wakeScheduler.tick()
    precondition(
        wakeStore.actions[0].fireAt == wakeClock.addingTimeInterval(600),
        "long tick gap resets idle start"
    )
}
print("Idle schedule cases passed")
