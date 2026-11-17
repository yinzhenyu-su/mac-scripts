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
    // 内置 bundleID 规则必须全部有显示名映射：未安装时不能显示裸 bundle ID。
    // 覆盖范围是 legacyDefaults ∪ residentRules（40 条）；Messages/Terminal 是系统 App，总走 NSWorkspace 解析名。
    let builtinBundleIDs = Set(
        RuleStore.legacyDefaults.union(RuleStore.residentRules)
            .filter { $0.match == .bundleID }
            .map(\.value)
    )
    let displayNameKeys = AppRule.builtinDisplayNameKeys
    precondition(builtinBundleIDs.count == 40, "builtin bundle ID rules")
    precondition(displayNameKeys.count == 40, "display-name mapping count")
    precondition(Set(displayNameKeys.keys) == builtinBundleIDs, "mapping covers exactly the builtin bundle ID rules")
    precondition(Set(displayNameKeys.values).count == 40, "display-name keys are unique")
    precondition(displayNameKeys.values.allSatisfy { $0.hasPrefix("rule.builtin.") })

    // 用 #filePath 推仓库根，避免依赖测试进程的 CWD；NSDictionary(contentsOfFile:) 同时校验 .strings 语法。
    let repoNeatQuit = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    for language in ["zh-Hans", "en"] {
        let path = repoNeatQuit.appendingPathComponent("NeatQuit/\(language).lproj/Localizable.strings").path
        guard let strings = NSDictionary(contentsOfFile: path) as? [String: String] else {
            preconditionFailure("cannot parse \(path) as a strings dictionary")
        }
        for (bundleID, key) in displayNameKeys {
            guard let value = strings[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                preconditionFailure("\(language) Localizable.strings is missing a value for \(key) (\(bundleID))")
            }
        }
    }

    // 测试/CI 环境未安装这些 App，也不能回退成裸 bundle ID（不断言具体安装态名称，避免机器差异）。
    let uninstalled = AppRule(match: .bundleID, value: "com.tinyspeck.slackmacgap")
    precondition(uninstalled.displayName != "com.tinyspeck.slackmacgap")
    precondition(AppRule.builtinDisplayNameKey(for: "com.tinyspeck.slackmacgap") == "rule.builtin.slack")
    precondition(AppRule.builtinDisplayNameKey(for: "com.example.unknown") == nil)
    // 按应用名匹配的旧规则保持原值；自建（无映射）的 bundleID 规则仍显示 bundle ID。
    precondition(AppRule(match: .applicationName, value: "Legacy Helper").displayName == "Legacy Helper")
    precondition(AppRule(match: .bundleID, value: "com.example.unknown").displayName == "com.example.unknown")
}
print("Builtin display name cases passed")

MainActor.assumeIsolated {
    let name = "fun.bgm.neatquit.onboarding-tests.\(UUID().uuidString)"
    let prefs = UserDefaults(suiteName: name)!
    // 旧域同样隔离：init 的默认参数会读真实旧域，不注入空 suite 会让用例结果依赖本机数据。
    let legacyName = "fun.bgm.neatquit.onboarding-legacy.\(UUID().uuidString)"
    let legacyPrefs = UserDefaults(suiteName: legacyName)!
    defer {
        prefs.removePersistentDomain(forName: name)
        legacyPrefs.removePersistentDomain(forName: legacyName)
    }
    let fresh = RuleStore(defaults: prefs, legacyDomainDefaults: legacyPrefs)
    precondition(fresh.needsOnboarding)
    precondition(!prefs.bool(forKey: "rules.legacyUsageSnapshot"))
    precondition(fresh.exceptionRules.contains(AppRule(match: .bundleID, value: "com.apple.Terminal")))
    precondition(RuleStore(defaults: prefs, legacyDomainDefaults: legacyPrefs).needsOnboarding)
    fresh.finishOnboarding()
    precondition(!RuleStore(defaults: prefs, legacyDomainDefaults: legacyPrefs).needsOnboarding)
    prefs.removePersistentDomain(forName: name)
    prefs.set(false, forKey: "enabled")
    let old = RuleStore(defaults: prefs, legacyDomainDefaults: legacyPrefs)
    // 没有已保存列表时一律播种当前默认名单（58 条），existing 只影响 onboarding 标记。
    precondition(!old.needsOnboarding && old.exceptionRules == RuleStore.defaultRules)
    prefs.removePersistentDomain(forName: name)
    prefs.set(Data("broken".utf8), forKey: "applicationRules")
    precondition(RuleStore(defaults: prefs, legacyDomainDefaults: legacyPrefs).exceptionRules == RuleStore.defaultRules)
    prefs.removePersistentDomain(forName: name)
    prefs.set(try! JSONEncoder().encode(Set<AppRule>()), forKey: "applicationRules")
    prefs.set("onlyListed", forKey: "ruleMode")
    let custom = RuleStore(defaults: prefs, legacyDomainDefaults: legacyPrefs)
    precondition(custom.mode == .onlyListed && custom.exceptionRules.isEmpty)
}
print("Onboarding migration cases passed")

MainActor.assumeIsolated {
    let currentName = "fun.bgm.neatquit.migration-current.\(UUID().uuidString)"
    let legacyName = "fun.bgm.neatquit.migration-legacy.\(UUID().uuidString)"
    let current = UserDefaults(suiteName: currentName)!
    let legacy = UserDefaults(suiteName: legacyName)!
    defer {
        current.removePersistentDomain(forName: currentName)
        legacy.removePersistentDomain(forName: legacyName)
    }

    let legacyRules: Set<AppRule> = [
        AppRule(match: .bundleID, value: "com.example.legacy.music"),
        AppRule(match: .applicationName, value: "Legacy Helper"),
    ]
    let legacyQuitRules: Set<AppRule> = [AppRule(match: .bundleID, value: "com.example.legacy.only")]

    func resetDomains() {
        current.removePersistentDomain(forName: currentName)
        legacy.removePersistentDomain(forName: legacyName)
    }

    // 迁移涉及的全部键的快照，用于验证第二次启动不改写任何值。
    func snapshot() -> NSDictionary {
        let keys = [
            "applicationRules", "applicationQuitRules", "ruleMode", "enabled", "keyboardEnabled",
            "license.legacyPro", "rules.onboardingHandled", "rules.legacyUsageSnapshot",
            "rules.migratedFromLegacyDomain",
        ]
        var values: [String: Any] = [:]
        for key in keys {
            if let value = current.object(forKey: key) { values[key] = value }
        }
        return values as NSDictionary
    }

    // 旧域有规则 + 新域为空 → 规则/模式/开关整体迁移，老用户保留 Pro 且不再看引导
    legacy.set(try! JSONEncoder().encode(legacyRules), forKey: "applicationRules")
    legacy.set(try! JSONEncoder().encode(legacyQuitRules), forKey: "applicationQuitRules")
    legacy.set("onlyListed", forKey: "ruleMode")
    legacy.set(true, forKey: "enabled")
    legacy.set(true, forKey: "keyboardEnabled")

    let migrated = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(migrated.mode == .onlyListed, "rule mode migrated from legacy domain")
    precondition(migrated.exceptionRules == legacyRules, "exception rules migrated from legacy domain")
    precondition(migrated.quitRules == legacyQuitRules, "quit rules migrated from legacy domain")
    precondition(current.bool(forKey: "enabled") && current.bool(forKey: "keyboardEnabled"), "switches migrated from legacy domain")
    precondition(!migrated.needsOnboarding, "migrated user does not see onboarding again")
    precondition(current.bool(forKey: "rules.legacyUsageSnapshot"), "legacy usage snapshot sees migrated data")
    precondition(current.string(forKey: "license.legacyPro") == "1", "legacy user keeps pro")
    precondition(current.bool(forKey: "rules.migratedFromLegacyDomain"), "migration marker written")

    // 幂等：标记存在后不再读旧域，也不改写新域任何值
    let afterMigration = snapshot()
    legacy.set(try! JSONEncoder().encode(Set([AppRule(match: .bundleID, value: "com.example.later")])), forKey: "applicationRules")
    let migratedAgain = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(migratedAgain.exceptionRules == legacyRules, "second launch does not re-import legacy rules")
    precondition(migratedAgain.mode == .onlyListed)
    precondition(snapshot() == afterMigration, "second launch does not rewrite defaults")

    // 新域已有用户自己的规则 → 不搬迁，旧域值不能覆盖新域，但迁移标记必须写
    resetDomains()
    let currentRules: Set<AppRule> = [AppRule(match: .bundleID, value: "com.example.current")]
    current.set(try! JSONEncoder().encode(currentRules), forKey: "applicationRules")
    current.set("allExceptListed", forKey: "ruleMode")
    legacy.set(try! JSONEncoder().encode(legacyRules), forKey: "applicationRules")
    legacy.set("onlyListed", forKey: "ruleMode")
    legacy.set(true, forKey: "keyboardEnabled")
    let untouched = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(untouched.exceptionRules == currentRules, "existing custom new-domain rules win")
    precondition(untouched.mode == .allExceptListed, "existing new-domain mode wins")
    precondition(current.bool(forKey: "keyboardEnabled"), "non-list settings are filled even when rules are kept")
    precondition(current.bool(forKey: "rules.migratedFromLegacyDomain"), "marker written without copying rules")

    // 跑过 1.6.x 的用户：新域列表是旧 onboarding 自动播种的 legacyDefaults，视为未编辑 → 用旧域规则替换
    resetDomains()
    current.set(try! JSONEncoder().encode(RuleStore.legacyDefaults), forKey: "applicationRules")
    current.set(false, forKey: "enabled")
    current.set(false, forKey: "rules.onboardingHandled")
    legacy.set(try! JSONEncoder().encode(legacyRules), forKey: "applicationRules")
    legacy.set("onlyListed", forKey: "ruleMode")
    legacy.set(true, forKey: "enabled")
    legacy.set(true, forKey: "keyboardEnabled")
    let replacedDefaults = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(replacedDefaults.exceptionRules == legacyRules, "seeded default list replaced by legacy rules")
    precondition(replacedDefaults.mode == .onlyListed, "seeded mode is filled from legacy domain")
    precondition(!current.bool(forKey: "enabled"), "existing switch value is never overwritten")
    precondition(current.bool(forKey: "keyboardEnabled"), "missing switch is filled from legacy domain")
    precondition(!replacedDefaults.needsOnboarding, "seeded user is marked as onboarded")
    let afterReplace = snapshot()
    let replacedAgain = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(replacedAgain.exceptionRules == legacyRules, "seeded replacement is not re-imported")
    precondition(snapshot() == afterReplace, "seeded replacement is idempotent")

    // 旧版播种的 25 条集合（legacyDefaults + 短信 + 终端）同样视为未编辑 → 替换
    resetDomains()
    current.set(try! JSONEncoder().encode(RuleStore.historicalAutoSeededRules[1]), forKey: "applicationRules")
    legacy.set(try! JSONEncoder().encode(legacyRules), forKey: "applicationRules")
    let replacedSeed = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(replacedSeed.exceptionRules == legacyRules, "old 25-rule seed list replaced by legacy rules")
    let afterSeedReplace = snapshot()
    _ = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(snapshot() == afterSeedReplace, "old seed replacement is idempotent")

    // 默认列表上用户自己加过项 → 不是自动播种的原始列表，保持现状
    resetDomains()
    var editedRules = RuleStore.defaultRules
    editedRules.insert(AppRule(match: .bundleID, value: "com.example.user-added"))
    current.set(try! JSONEncoder().encode(editedRules), forKey: "applicationRules")
    current.set(true, forKey: "rules.onboardingHandled")
    legacy.set(try! JSONEncoder().encode(legacyRules), forKey: "applicationRules")
    let editedKept = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(editedKept.exceptionRules == editedRules, "user-edited default list is not replaced")
    let afterEdited = snapshot()
    _ = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(snapshot() == afterEdited, "edited list stays unchanged on second launch")

    // 空列表是用户主动清空的结果，不能当成播种列表替换
    resetDomains()
    current.set(try! JSONEncoder().encode(Set<AppRule>()), forKey: "applicationRules")
    current.set(true, forKey: "rules.onboardingHandled")
    legacy.set(try! JSONEncoder().encode(legacyRules), forKey: "applicationRules")
    let clearedKept = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(clearedKept.exceptionRules.isEmpty, "deliberately cleared list is not replaced")
    let afterCleared = snapshot()
    _ = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(snapshot() == afterCleared, "cleared list stays unchanged on second launch")

    // 旧域不存在 → 无副作用（不写规则数据、不伪造 Pro），只写标记
    resetDomains()
    current.set(true, forKey: "rules.onboardingHandled")
    let noLegacy = RuleStore(defaults: current, legacyDomainDefaults: nil)
    precondition(noLegacy.exceptionRules == RuleStore.defaultRules)
    precondition(current.object(forKey: "applicationRules") == nil, "no rule data written without a legacy domain")
    precondition(current.object(forKey: "license.legacyPro") == nil, "no pro granted without legacy usage")
    precondition(current.bool(forKey: "rules.migratedFromLegacyDomain"), "marker written even without legacy domain")

    // 旧域数据损坏 → 坏数据不搬、不作为 Pro 依据，也不影响新域
    resetDomains()
    current.set(true, forKey: "rules.onboardingHandled")
    legacy.set(Data("broken-legacy-rules".utf8), forKey: "applicationRules")
    let corruptLegacy = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(corruptLegacy.exceptionRules == RuleStore.defaultRules)
    precondition(current.object(forKey: "applicationRules") == nil, "broken legacy rules are not copied")
    precondition(current.object(forKey: "license.legacyPro") == nil, "broken legacy data is not usage evidence")
    precondition(current.bool(forKey: "rules.migratedFromLegacyDomain"))

    // 标记是一次性的：首次扫描时旧域为空，之后旧域再出现数据也不会被回灌
    resetDomains()
    current.set(true, forKey: "rules.onboardingHandled")
    _ = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(current.bool(forKey: "rules.migratedFromLegacyDomain"))
    legacy.set(try! JSONEncoder().encode(legacyRules), forKey: "applicationRules")
    let scannedOnce = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(scannedOnce.exceptionRules == RuleStore.defaultRules, "migration runs only once per domain")
    precondition(current.object(forKey: "applicationRules") == nil)

    // Pro 放宽：已经跑过 1.6.x 的用户（当前域有 trialStart/migrated/lastValidatedAt）也要补旧版 Pro
    resetDomains()
    current.set(try! JSONEncoder().encode(RuleStore.historicalAutoSeededRules[1]), forKey: "applicationRules")
    current.set("2026-01-01T00:00:00Z", forKey: "license.trialStart")
    current.set("1", forKey: "license.migrated")
    current.set(1_700_000_000.0, forKey: "license.lastValidatedAt")
    legacy.set(try! JSONEncoder().encode(legacyRules), forKey: "applicationRules")
    let upgradedPro = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(upgradedPro.exceptionRules == legacyRules, "already-upgraded user gets rules back")
    precondition(current.string(forKey: "license.legacyPro") == "1", "trial/migrated state does not block pro restore")
    let afterUpgradedPro = snapshot()
    _ = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(snapshot() == afterUpgradedPro, "pro restore is idempotent")

    // 已有真实 license.key 的付费用户 → 不写 legacyPro，避免混淆真实授权状态
    resetDomains()
    current.set(try! JSONEncoder().encode(RuleStore.historicalAutoSeededRules[1]), forKey: "applicationRules")
    current.set("NQ-TEST-KEY-0000-0000", forKey: "license.key")
    legacy.set(try! JSONEncoder().encode(legacyRules), forKey: "applicationRules")
    let licensed = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(licensed.exceptionRules == legacyRules, "rules still migrate for a licensed user")
    precondition(current.object(forKey: "license.legacyPro") == nil, "real license key blocks legacy pro")

    // 已有 legacyPro（值不是 "1"）→ 不覆盖
    resetDomains()
    current.set(try! JSONEncoder().encode(RuleStore.historicalAutoSeededRules[1]), forKey: "applicationRules")
    current.set("keep-me", forKey: "license.legacyPro")
    legacy.set(try! JSONEncoder().encode(legacyRules), forKey: "applicationRules")
    _ = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(current.string(forKey: "license.legacyPro") == "keep-me", "existing legacy pro is never overwritten")

    // 解耦：新域列表是用户自定义（不迁移列表）时，旧域的设置键仍按“只补 nil”补齐
    resetDomains()
    current.set(try! JSONEncoder().encode(currentRules), forKey: "applicationRules")
    current.set("allExceptListed", forKey: "ruleMode")
    legacy.set(try! JSONEncoder().encode(legacyRules), forKey: "applicationRules")
    legacy.set(try! JSONEncoder().encode(legacyQuitRules), forKey: "applicationQuitRules")
    legacy.set("onlyListed", forKey: "ruleMode")
    legacy.set(false, forKey: "enabled")
    legacy.set(true, forKey: "keyboardEnabled")
    let decoupled = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(decoupled.exceptionRules == currentRules, "custom rule list is neither merged nor replaced")
    precondition(decoupled.mode == .allExceptListed, "existing mode is not overwritten")
    precondition(decoupled.quitRules == legacyQuitRules, "missing quit rules are filled")
    precondition(current.object(forKey: "enabled") != nil && !current.bool(forKey: "enabled"), "missing enabled is filled")
    precondition(current.bool(forKey: "keyboardEnabled"), "missing keyboardEnabled is filled")
    precondition(!decoupled.needsOnboarding, "settings-only migration marks the user as onboarded")
    let afterDecoupled = snapshot()
    _ = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(snapshot() == afterDecoupled, "settings-only migration is idempotent")

    // 新域已有 keyboardEnabled=false → 不被旧域覆盖
    resetDomains()
    current.set(try! JSONEncoder().encode(currentRules), forKey: "applicationRules")
    current.set(false, forKey: "keyboardEnabled")
    legacy.set(try! JSONEncoder().encode(legacyQuitRules), forKey: "applicationQuitRules")
    legacy.set(true, forKey: "keyboardEnabled")
    let keepSwitch = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(!current.bool(forKey: "keyboardEnabled"), "existing keyboardEnabled wins")
    precondition(keepSwitch.quitRules == legacyQuitRules, "other missing settings are still filled")
    let afterKeepSwitch = snapshot()
    _ = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(snapshot() == afterKeepSwitch, "existing switch case is idempotent")

    // 旧域 applicationQuitRules 损坏 → 跳过该键，其他设置键照常补齐
    resetDomains()
    current.set(try! JSONEncoder().encode(currentRules), forKey: "applicationRules")
    legacy.set(Data("broken-quit-rules".utf8), forKey: "applicationQuitRules")
    legacy.set("onlyListed", forKey: "ruleMode")
    legacy.set(true, forKey: "enabled")
    let corruptQuit = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(corruptQuit.quitRules.isEmpty, "broken legacy quit rules are skipped")
    precondition(current.object(forKey: "applicationQuitRules") == nil, "broken quit rules are not copied")
    precondition(corruptQuit.mode == .onlyListed, "other settings still migrate")
    precondition(current.bool(forKey: "enabled"), "other missing settings are filled")
    let afterCorruptQuit = snapshot()
    _ = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(snapshot() == afterCorruptQuit, "partial settings migration is idempotent")
}
print("Legacy domain migration cases passed")

MainActor.assumeIsolated {
    // 名单结构：历史 23 条冻结 + 常驻后台 33 条 + Messages/Terminal 2 条 = 统一默认 58 条
    precondition(RuleStore.legacyDefaults.count == 23, "frozen legacy default list")
    precondition(RuleStore.residentRules.count == 33, "resident app list")
    let historicalNewUserExtras: Set<AppRule> = [
        AppRule(match: .bundleID, value: "com.apple.MobileSMS"),
        AppRule(match: .bundleID, value: "com.apple.Terminal"),
    ]
    precondition(RuleStore.defaultRules == RuleStore.legacyDefaults
        .union(RuleStore.residentRules)
        .union(historicalNewUserExtras))
    precondition(RuleStore.defaultRules.count == 58, "single unified default list")
    precondition(RuleStore.historicalAutoSeededRules.count == 2, "two historical auto-seeded snapshots")
    precondition(RuleStore.historicalAutoSeededRules.contains(RuleStore.legacyDefaults))
    precondition(RuleStore.historicalAutoSeededRules[1] == RuleStore.legacyDefaults.union(historicalNewUserExtras))
    precondition(RuleStore.historicalAutoSeededRules[1].count == 25)

    let currentName = "fun.bgm.neatquit.defaults-revision.\(UUID().uuidString)"
    let legacyName = "fun.bgm.neatquit.defaults-revision-legacy.\(UUID().uuidString)"
    let current = UserDefaults(suiteName: currentName)!
    let legacy = UserDefaults(suiteName: legacyName)!
    defer {
        current.removePersistentDomain(forName: currentName)
        legacy.removePersistentDomain(forName: legacyName)
    }

    func resetDomains() {
        current.removePersistentDomain(forName: currentName)
        legacy.removePersistentDomain(forName: legacyName)
    }
    func storedData() -> Data? { current.data(forKey: "applicationRules") }
    func storedRules() -> Set<AppRule>? {
        storedData().flatMap { try? JSONDecoder().decode(Set<AppRule>.self, from: $0) }
    }

    // 旧版自动播种的 23 条 → 一次性升级为当前默认名单（58）
    resetDomains()
    current.set(try! JSONEncoder().encode(RuleStore.historicalAutoSeededRules[0]), forKey: "applicationRules")
    let from23 = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(from23.exceptionRules == RuleStore.defaultRules, "auto-seeded 23 upgraded to the default list")
    precondition(storedRules() == RuleStore.defaultRules, "23-rule upgrade is persisted")
    precondition(current.integer(forKey: "rules.defaultsRevision") == 2, "revision marker written")
    let after23 = storedData()
    _ = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(storedData() == after23, "23-rule upgrade is idempotent")

    // 旧版自动播种的 25 条 → 同样升级为 58
    resetDomains()
    current.set(try! JSONEncoder().encode(RuleStore.historicalAutoSeededRules[1]), forKey: "applicationRules")
    let from25 = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(from25.exceptionRules == RuleStore.defaultRules, "auto-seeded 25 upgraded to the default list")
    precondition(storedRules() == RuleStore.defaultRules)
    precondition(current.integer(forKey: "rules.defaultsRevision") == 2)
    let after25 = storedData()
    _ = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(storedData() == after25, "25-rule upgrade is idempotent")

    // 用户编辑过的列表（58+1）绝不改动：字节层面逐字节一致，但仍写升级标记（只扫一次）
    resetDomains()
    var customRules = RuleStore.defaultRules
    customRules.insert(AppRule(match: .bundleID, value: "com.example.custom"))
    let customBytes = try! JSONEncoder().encode(customRules)
    current.set(customBytes, forKey: "applicationRules")
    let keepCustom = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(keepCustom.exceptionRules == customRules, "edited list is not replaced")
    precondition(storedData() == customBytes, "edited list bytes are byte-identical")
    precondition(current.integer(forKey: "rules.defaultsRevision") == 2, "marker still written for edited list")
    let afterCustom = storedData()
    _ = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(storedData() == afterCustom, "edited list stays untouched on second launch")

    // 空列表（用户主动清空）同样不动
    resetDomains()
    let emptyBytes = try! JSONEncoder().encode(Set<AppRule>())
    current.set(emptyBytes, forKey: "applicationRules")
    let keepEmpty = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(keepEmpty.exceptionRules.isEmpty, "empty list is not replaced")
    precondition(storedData() == emptyBytes, "empty list bytes are byte-identical")
    precondition(current.integer(forKey: "rules.defaultsRevision") == 2)

    // 任意非历史快照的列表都不升级：显式断言配置推广前后逐字节一致（58 缺 1 条）
    resetDomains()
    var nearlyDefault = RuleStore.defaultRules
    nearlyDefault.remove(AppRule(match: .bundleID, value: "com.docker.docker"))
    let nearlyBytes = try! JSONEncoder().encode(nearlyDefault)
    current.set(nearlyBytes, forKey: "applicationRules")
    let keepNearly = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(keepNearly.exceptionRules == nearlyDefault, "near-default list is not replaced")
    precondition(storedData() == nearlyBytes, "near-default list bytes are byte-identical")

    // 数据损坏：内存回退 58、备份原始字节、主键原始字节不被改写
    resetDomains()
    let brokenDefaults = Data("broken-defaults".utf8)
    current.set(brokenDefaults, forKey: "applicationRules")
    let recovered = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(recovered.exceptionRules == RuleStore.defaultRules, "corrupt list falls back to the default list")
    precondition(current.data(forKey: "applicationRules.unreadable") == brokenDefaults, "corrupt list is backed up")
    precondition(storedData() == brokenDefaults, "corrupt bytes are not rewritten")
    precondition(current.integer(forKey: "rules.defaultsRevision") == 2)

    // 全新安装：播种 defaultRules(58)，仍然需要引导
    resetDomains()
    let fresh = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(fresh.needsOnboarding, "fresh install still needs onboarding")
    precondition(fresh.exceptionRules == RuleStore.defaultRules, "fresh install seeds the unified default list")
    precondition(storedRules() == RuleStore.defaultRules)
    let afterFresh = storedData()
    _ = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(storedData() == afterFresh, "fresh install seeding is idempotent")

    // 有使用记录但从未保存列表：单一分支直接播种 58（existing 只影响 onboarding 标记）
    resetDomains()
    current.set(true, forKey: "enabled")
    let returning = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    precondition(!returning.needsOnboarding)
    precondition(returning.exceptionRules == RuleStore.defaultRules, "returning user also seeds the unified default list")
    precondition(storedRules() == RuleStore.defaultRules)
}
print("Default rules revision cases passed")

MainActor.assumeIsolated {
    let currentName = "fun.bgm.neatquit.reset-tests.\(UUID().uuidString)"
    let legacyName = "fun.bgm.neatquit.reset-legacy.\(UUID().uuidString)"
    let current = UserDefaults(suiteName: currentName)!
    let legacy = UserDefaults(suiteName: legacyName)!
    defer {
        current.removePersistentDomain(forName: currentName)
        legacy.removePersistentDomain(forName: legacyName)
    }

    func storedRules(forKey key: String) -> Set<AppRule>? {
        current.data(forKey: key).flatMap { try? JSONDecoder().decode(Set<AppRule>.self, from: $0) }
    }
    func metadataSnapshot() -> NSDictionary {
        let keys = [
            "rules.defaultsRevision", "rules.migratedFromLegacyDomain",
            "rules.onboardingHandled", "rules.legacyUsageSnapshot",
            "license.legacyPro", "license.key",
        ]
        var values: [String: Any] = [:]
        for key in keys {
            if let value = current.object(forKey: key) { values[key] = value }
        }
        return values as NSDictionary
    }

    // 排除模式：重置回内置默认例外名单
    let store = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    let customRule = AppRule(match: .bundleID, value: "com.example.custom")
    store.addApplication(bundleID: customRule.value)
    precondition(store.exceptionRules.contains(customRule))
    let metadataBefore = metadataSnapshot()
    var policies: [RulePolicy] = []
    store.onChange = { policies.append($0) }

    store.resetActiveRulesToDefault()
    precondition(store.exceptionRules == RuleStore.defaultRules, "exclude mode resets to the builtin default list")
    precondition(store.policy == RulePolicy(mode: .allExceptListed, rules: RuleStore.defaultRules))
    precondition(storedRules(forKey: "applicationRules") == RuleStore.defaultRules, "reset is persisted")
    precondition(policies.count == 1 && policies[0] == store.policy, "reset notifies onChange once")
    precondition(metadataSnapshot() == metadataBefore, "reset does not touch migration or license state")

    // 已等于默认时再次重置：幂等，不产生额外存储变化
    let storedAfterReset = current.data(forKey: "applicationRules")
    store.resetActiveRulesToDefault()
    precondition(store.exceptionRules == RuleStore.defaultRules)
    precondition(current.data(forKey: "applicationRules") == storedAfterReset, "second reset writes the same list")
    precondition(metadataSnapshot() == metadataBefore, "second reset keeps metadata")

    // 仅包含模式：清空 quitRules，排除列表与元数据都不动
    let onlyStore = RuleStore(defaults: current, legacyDomainDefaults: legacy)
    onlyStore.setMode(.onlyListed)
    onlyStore.addApplication(bundleID: "com.example.only")
    precondition(storedRules(forKey: "applicationQuitRules")?.isEmpty == false)
    let exceptionBefore = onlyStore.exceptionRules
    let exceptionStoredBefore = current.data(forKey: "applicationRules")
    let metadataBeforeOnly = metadataSnapshot()
    var onlyPolicies: [RulePolicy] = []
    onlyStore.onChange = { onlyPolicies.append($0) }

    onlyStore.resetActiveRulesToDefault()
    precondition(onlyStore.quitRules.isEmpty, "only-listed reset clears quit rules")
    precondition(storedRules(forKey: "applicationQuitRules")?.isEmpty == true, "cleared quit rules are persisted")
    precondition(onlyStore.exceptionRules == exceptionBefore, "exclude list is untouched in only-listed mode")
    precondition(current.data(forKey: "applicationRules") == exceptionStoredBefore, "exclude list storage is untouched")
    precondition(onlyStore.policy == RulePolicy(mode: .onlyListed, rules: []))
    precondition(onlyPolicies.count == 1 && onlyPolicies[0] == onlyStore.policy, "only-listed reset notifies onChange")
    precondition(metadataSnapshot() == metadataBeforeOnly, "only-listed reset keeps migration and license state")
}
print("Reset to default rules cases passed")

MainActor.assumeIsolated {
    let name = "fun.bgm.neatquit.unreadable-tests.\(UUID().uuidString)"
    let current = UserDefaults(suiteName: name)!
    defer { current.removePersistentDomain(forName: name) }

    current.set(true, forKey: "rules.onboardingHandled")
    let brokenRules = Data("broken-rules".utf8)
    let brokenQuitRules = Data("broken-quit-rules".utf8)
    current.set(brokenRules, forKey: "applicationRules")
    current.set(brokenQuitRules, forKey: "applicationQuitRules")

    let store = RuleStore(defaults: current, legacyDomainDefaults: nil)
    precondition(store.exceptionRules == RuleStore.defaultRules, "corrupt rules fall back to the default list")
    precondition(store.quitRules.isEmpty, "corrupt quit rules fall back to empty list")
    precondition(current.data(forKey: "applicationRules.unreadable") == brokenRules, "original rules data backed up")
    precondition(current.data(forKey: "applicationQuitRules.unreadable") == brokenQuitRules, "original quit rules data backed up")
    precondition(RuleStore.unreadableBackupKey(for: "applicationRules") == "applicationRules.unreadable")
    let logMessage = RuleStore.decodeFailureLogMessage(key: "applicationRules", reason: "decode test")
    precondition(logMessage.contains("applicationRules.unreadable"), "log message points at the backup")
    precondition(RuleStore.logCategory == "rules")
    precondition(RuleStore.logSubsystem == (Bundle.main.bundleIdentifier ?? "fun.bgm.neatquit"))

    // 已有备份不被后来的坏数据覆盖
    current.set(Data("broken-again".utf8), forKey: "applicationRules")
    _ = RuleStore(defaults: current, legacyDomainDefaults: nil)
    precondition(current.data(forKey: "applicationRules.unreadable") == brokenRules, "first backup is kept")

    // 后续增删规则只写主键，不删除备份
    store.addApplication(bundleID: "com.example.after-corrupt")
    precondition(store.exceptionRules.contains(AppRule(match: .bundleID, value: "com.example.after-corrupt")))
    precondition(current.data(forKey: "applicationRules.unreadable") == brokenRules, "editing rules keeps the backup")
    precondition(current.data(forKey: "applicationRules") != brokenRules, "new rules replace the corrupt blob")
}
print("Unreadable rule backup cases passed")

MainActor.assumeIsolated {
    let name = "fun.bgm.neatquit.remote-tests.\(UUID().uuidString)"
    let prefs = UserDefaults(suiteName: name)!
    defer { prefs.removePersistentDomain(forName: name) }

    let writer = RuleStore(defaults: prefs, legacyDomainDefaults: nil)
    let reader = RuleStore(defaults: prefs, legacyDomainDefaults: nil)
    let remoteRule = AppRule(match: .bundleID, value: "com.example.remote")
    writer.addApplication(bundleID: remoteRule.value)
    precondition(!reader.exceptionRules.contains(remoteRule), "reader is stale before the broadcast is applied")

    let savedRules = prefs.data(forKey: "applicationRules")
    reader.applyRemoteChange()
    precondition(reader.exceptionRules == writer.exceptionRules, "remote change refreshes in-memory rules")
    precondition(prefs.data(forKey: "applicationRules") == savedRules, "remote refresh does not write to disk")

    writer.setMode(.onlyListed)
    precondition(reader.mode == .allExceptListed)
    reader.applyRemoteChange()
    precondition(reader.mode == .onlyListed, "remote change refreshes mode")

    // 没有变化时刷新是 no-op：不写盘也不重复通知，因此不会和广播形成保存回环
    let afterRefresh = prefs.data(forKey: "applicationRules")
    var notified = 0
    reader.onChange = { _ in notified += 1 }
    reader.applyRemoteChange()
    precondition(notified == 0, "no-op refresh does not notify")
    precondition(prefs.data(forKey: "applicationRules") == afterRefresh, "no-op refresh does not write")
}
print("Multi-instance rule refresh cases passed")

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
