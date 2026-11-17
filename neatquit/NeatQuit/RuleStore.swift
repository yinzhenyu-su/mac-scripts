import AppKit
import Combine
import OSLog

struct AppRule: Codable, Hashable, Identifiable {
    enum Match: String, Codable {
        case bundleID
        case applicationName
    }

    let match: Match
    let value: String

    var id: String { "\(match.rawValue):\(value)" }
    var displayName: String {
        switch match {
        case .applicationName:
            return value
        case .bundleID:
            // 已安装时优先用系统解析出的 App 名；未安装时用内置映射，避免显示裸 bundle ID。
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value) {
                return url.deletingPathExtension().lastPathComponent
            }
            if let key = Self.builtinDisplayNameKey(for: value) {
                return NSLocalizedString(key, comment: "")
            }
            return value
        }
    }
    var detail: String {
        match == .bundleID ? value : NSLocalizedString("rule.detail.applicationName", comment: "")
    }

    /// 内置默认名单里的 bundleID → 本地化显示名 key。
    /// 只覆盖内置名单（legacy 7 条 + resident 33 条 = 40 条），用户自建的规则仍显示 bundle ID。
    static let builtinDisplayNameKeys: [String: String] = [
        "com.tencent.xinWeChat": "rule.builtin.wechat",
        "com.tencent.qq": "rule.builtin.qq",
        "com.tencent.qqmusic": "rule.builtin.qqmusic",
        "com.spotify.client": "rule.builtin.spotify",
        "com.apple.Music": "rule.builtin.music",
        "com.meta.Telegram": "rule.builtin.telegram",
        "com.netease.163music": "rule.builtin.netease-music",
        "com.sogou.inputmethod.sogou": "rule.builtin.sogou-input",
        "com.baidu.inputmethod.BaiduIM": "rule.builtin.baidu-ime",
        "org.pqrs.Karabiner-Elements.Settings": "rule.builtin.karabiner",
        "com.logi.optionsplus": "rule.builtin.logi-options",
        "com.caldis.Mos": "rule.builtin.mos",
        "com.raycast.macos": "rule.builtin.raycast",
        "com.runningwithcrayons.Alfred": "rule.builtin.alfred",
        "eu.exelban.Stats": "rule.builtin.stats",
        "com.if.Amphetamine": "rule.builtin.amphetamine",
        "com.surteesstudios.Bartender": "rule.builtin.bartender",
        "com.knollsoft.Rectangle": "rule.builtin.rectangle",
        "com.nssurge.surge-mac": "rule.builtin.surge",
        "io.github.clash-verge-rev.clash-verge-rev": "rule.builtin.clash-verge",
        "io.tailscale.ipn.macos": "rule.builtin.tailscale",
        "io.tailscale.ipn.macsys": "rule.builtin.tailscale-standalone",
        "com.wireguard.macos": "rule.builtin.wireguard",
        "com.cloudflare.1dot1dot1dot1.macos": "rule.builtin.warp",
        "com.getdropbox.dropbox": "rule.builtin.dropbox",
        "com.microsoft.OneDrive": "rule.builtin.onedrive",
        "com.google.drivefs": "rule.builtin.google-drive",
        "net.nutstore.NutstoreJavaBE": "rule.builtin.nutstore",
        "com.baidu.BaiduNetdisk-mac": "rule.builtin.baidu-netdisk",
        "com.tinyspeck.slackmacgap": "rule.builtin.slack",
        "com.hnc.Discord": "rule.builtin.discord",
        "com.microsoft.teams2": "rule.builtin.teams",
        "com.bytedance.macos.feishu": "rule.builtin.feishu",
        "com.electron.lark": "rule.builtin.feishu-legacy",
        "com.tencent.WeWorkMac": "rule.builtin.wecom",
        "org.whispersystems.signal-desktop": "rule.builtin.signal",
        "net.whatsapp.WhatsApp": "rule.builtin.whatsapp",
        "pl.maketheweb.cleanshotx": "rule.builtin.cleanshot",
        "com.p0deje.Maccy": "rule.builtin.maccy",
        "com.docker.docker": "rule.builtin.docker",
    ]

    static func builtinDisplayNameKey(for bundleID: String) -> String? {
        builtinDisplayNameKeys[bundleID]
    }

    func matches(searchQuery query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return displayName.localizedCaseInsensitiveContains(trimmed)
            || value.localizedCaseInsensitiveContains(trimmed)
            || detail.localizedCaseInsensitiveContains(trimmed)
    }
}

enum RuleMode: String, Codable, CaseIterable {
    /// 默认模式：自动退出所有 App，列表中的保持运行。
    case allExceptListed
    /// 反向模式：只自动退出列表中的 App。
    case onlyListed
}

struct RulePolicy: Equatable {
    var mode: RuleMode
    var rules: Set<AppRule>

    static let `default` = RulePolicy(mode: .allExceptListed, rules: [])
}


struct CloseDecision {
    enum Action: Equatable {
        case close
        case quit
    }

    static func action(bundleID: String?, applicationName: String?, isStandardWindow: Bool, standardWindowCount: Int?, policy: RulePolicy) -> Action {
        guard isStandardWindow, standardWindowCount == 1,
              bundleID != nil || applicationName != nil else { return .close }
        let matched = (bundleID.map { policy.rules.contains(AppRule(match: .bundleID, value: $0)) } ?? false)
            || (applicationName.map { policy.rules.contains(AppRule(match: .applicationName, value: $0)) } ?? false)
        switch policy.mode {
        case .allExceptListed:
            return matched ? .close : .quit
        case .onlyListed:
            return matched ? .quit : .close
        }
    }

    static func shouldMonitorFullScreenClose(bundleID: String?, applicationName: String?, isStandardWindow: Bool, policy: RulePolicy) -> Bool {
        action(bundleID: bundleID, applicationName: applicationName, isStandardWindow: isStandardWindow, standardWindowCount: 1, policy: policy) == .quit
    }

    static func shouldQuitAfterKeyboardClose(initialAction: Action, remainingWindowCount: Int?, remainingVisibleWindowCount: Int?, targetStillRunning: Bool) -> Bool {
        initialAction == .quit && targetStillRunning && remainingWindowCount != nil
            && (remainingWindowCount == 0 || remainingVisibleWindowCount == 0)
    }

    static func isScreenSizedWindow(_ windowSize: CGSize, screenSizes: [CGSize]) -> Bool {
        screenSizes.contains { windowSize.width >= $0.width * 0.95 && windowSize.height >= $0.height * 0.95 }
    }

    static func otherWindowCount(_ windowIDs: [UInt32]?, excluding closingWindowID: UInt32?) -> Int? {
        guard let windowIDs, let closingWindowID else { return nil }
        return windowIDs.filter { $0 != closingWindowID }.count
    }

    static func shouldQuitAfterFullScreenClose(remainingStandardWindowCount: Int?, remainingVisibleWindowCount: Int?, remainingScreenSizedWindowCount: Int?) -> Bool {
        remainingStandardWindowCount == 0 && remainingVisibleWindowCount == 0 && remainingScreenSizedWindowCount == 0
    }

    static func shouldQuitAfterConfirmedFullScreenClose(previousSampleWasEmpty: Bool, currentSampleIsEmpty: Bool) -> Bool {
        previousSampleWasEmpty && currentSampleIsEmpty
    }
}

/// v1.3.5 及更早版本的 Bundle ID。1.3.6 换成 fun.bgm.neatquit 后 UserDefaults 域随之改变，
/// 老用户的规则仍留在旧域，需要在启动时一次性搬过来。
private let legacyBundleID = "com.yinzhenyu.smartclose"

@MainActor
final class RuleStore: ObservableObject {
    @Published private(set) var mode: RuleMode {
        didSet {
            guard !isApplyingRemoteChange else { return }
            defaults.set(mode.rawValue, forKey: Self.modeKey)
            notifyChange()
            broadcastChange()
        }
    }

    @Published private(set) var exceptionRules: Set<AppRule> {
        didSet {
            guard !isApplyingRemoteChange else { return }
            save(exceptionRules, forKey: Self.exceptionStorageKey)
            notifyChange()
            broadcastChange()
        }
    }

    @Published private(set) var quitRules: Set<AppRule> {
        didSet {
            guard !isApplyingRemoteChange else { return }
            save(quitRules, forKey: Self.quitStorageKey)
            notifyChange()
            broadcastChange()
        }
    }

    var onChange: ((RulePolicy) -> Void)?
    private static let modeKey = "ruleMode"
    private static let exceptionStorageKey = "applicationRules"
    private static let quitStorageKey = "applicationQuitRules"
    private static let legacyUsageSnapshotKey = "rules.legacyUsageSnapshot"
    /// 旧域只扫描一次；即使旧域数据损坏也写标记，避免每次启动都重复读旧域。
    private static let legacyMigrationMarkerKey = "rules.migratedFromLegacyDomain"
    private static let legacyProKey = "license.legacyPro"
    /// 内置默认名单版本：调整内置名单时 +1，用于把未编辑过的旧版自动播种名单一次性升级到当前默认。
    private static let defaultsRevisionKey = "rules.defaultsRevision"
    private static let defaultsRevision = 2
    private static let unreadableSuffix = ".unreadable"
    nonisolated static let notificationSourceKey = "source"
    /// 同一 Bundle ID 的多个实例之间广播规则变更。
    static let rulesDidChangeNotification = Notification.Name("fun.bgm.neatquit.rulesDidChange")
    static let logSubsystem = Bundle.main.bundleIdentifier ?? "fun.bgm.neatquit"
    static let logCategory = "rules"
    private static let logger = Logger(subsystem: logSubsystem, category: logCategory)

    var activeRules: Set<AppRule> {
        mode == .allExceptListed ? exceptionRules : quitRules
    }

    var policy: RulePolicy {
        RulePolicy(mode: mode, rules: activeRules)
    }

    /// v1.5/v1.6 使用的内置名单（23 条）。已冻结：只作为历史快照，
    /// 用于识别旧版自动播种过的列表（迁移指纹 + 默认名单升级判断）。
    /// 新增默认项一律加到 residentRules，不要再改这里。
    static let legacyDefaults: Set<AppRule> = Set([
                "com.tencent.xinWeChat", "com.tencent.qq", "com.tencent.qqmusic",
                "com.spotify.client", "com.apple.Music", "com.meta.Telegram",
                "com.netease.163music",
            ].map { AppRule(match: .bundleID, value: $0) } + [
                "OrbStack", "QQ", "QQMusic", "WeType", "Hammerspoon",
                "Swish", "Bob", "Ice", "PopClip",
                "ZeroTier", "ClashX Meta", "v2rayN", "ClashX Pro", "Longshot",
                "BetterTouchTool", "DingTalk",
            ].map { AppRule(match: .applicationName, value: $0) })
    /// 需要常驻后台的应用：默认不自动退出。全部按 bundleID 匹配，避免应用名误匹配。
    static let residentRules: Set<AppRule> = Set([
        // 输入法 / 键盘 / 指针增强
        "com.sogou.inputmethod.sogou", "com.baidu.inputmethod.BaiduIM",
        "org.pqrs.Karabiner-Elements.Settings", "com.logi.optionsplus", "com.caldis.Mos",
        // 启动器 / 菜单栏 / 窗口管理
        "com.raycast.macos", "com.runningwithcrayons.Alfred", "eu.exelban.Stats",
        "com.if.Amphetamine", "com.surteesstudios.Bartender", "com.knollsoft.Rectangle",
        // 网络 / VPN / 代理（Tailscale 两种分发形态都覆盖：App Store 版 .macos、独立安装版 .macsys）
        "com.nssurge.surge-mac", "io.github.clash-verge-rev.clash-verge-rev",
        "io.tailscale.ipn.macos", "io.tailscale.ipn.macsys", "com.wireguard.macos", "com.cloudflare.1dot1dot1dot1.macos",
        // 同步 / 网盘
        "com.getdropbox.dropbox", "com.microsoft.OneDrive", "com.google.drivefs",
        "net.nutstore.NutstoreJavaBE", "com.baidu.BaiduNetdisk-mac",
        // 通讯 / 协作
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.microsoft.teams2",
        "com.bytedance.macos.feishu", "com.electron.lark", "com.tencent.WeWorkMac",
        "org.whispersystems.signal-desktop", "net.whatsapp.WhatsApp",
        // 截图 / 剪贴板
        "pl.maketheweb.cleanshotx", "com.p0deje.Maccy",
        // 开发工具（常驻菜单栏 / 后台服务）
        "com.docker.docker",
    ].map { AppRule(match: .bundleID, value: $0) })

    /// 旧版只给全新安装播种的两个通讯 App（Messages / Terminal）。
    /// 现在已并入统一默认名单，这里保留为冻结的历史指纹，仅用于识别 1.6.0/1.6.1 播种过的 25 条旧列表。
    private static let historicalNewUserSeedExtras: Set<AppRule> = Set(
        ["com.apple.MobileSMS", "com.apple.Terminal"].map { AppRule(match: .bundleID, value: $0) })

    /// 唯一的内置默认名单：历史名单 ∪ 常驻后台应用 ∪ 两个通讯 App。
    /// 全新安装、升级播种、解码失败回退、重置按钮全部用这一份，不再区分新/老用户。
    static let defaultRules: Set<AppRule> = legacyDefaults.union(residentRules).union(historicalNewUserSeedExtras)

    static let onboardingKey = "rules.onboardingHandled"
    /// 旧版自动播种过的两种集合快照（23 条 / 25 条），只用于识别“从未编辑过的默认列表”：
    /// 旧域迁移指纹与默认名单升级判断都以它为准。
    static let historicalAutoSeededRules: [Set<AppRule>] = [
        legacyDefaults,
        legacyDefaults.union(historicalNewUserSeedExtras),
    ]
    private let defaults: UserDefaults
    /// 装载远端变更期间为 true：didSet 只更新内存，不写盘、不广播，避免实例之间互相覆盖。
    private var isApplyingRemoteChange = false
    private var localObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    var needsOnboarding: Bool { !defaults.bool(forKey: Self.onboardingKey) }
    func finishOnboarding() { defaults.set(true, forKey: Self.onboardingKey) }

    init(defaults: UserDefaults = .standard,
         legacyDomainDefaults: UserDefaults? = UserDefaults(suiteName: legacyBundleID)) {
        self.defaults = defaults
        // 必须在计算使用痕迹、播种引导之前完成：迁移过来的数据要参与这两个判断。
        Self.migrateLegacyDomainIfNeeded(defaults: defaults, legacy: legacyDomainDefaults)
        // 只升级“旧版自动播种、用户从未编辑过”的名单；用户配置过的列表一律不动。
        Self.upgradeDefaultRulesIfNeeded(defaults: defaults)

        if defaults.object(forKey: Self.legacyUsageSnapshotKey) == nil {
            defaults.set(["keyboardEnabled", "applicationRules", "enabled"].contains { defaults.object(forKey: $0) != nil }, forKey: Self.legacyUsageSnapshotKey)
        }
        let existing = defaults.dictionaryRepresentation().keys.contains {
            ["enabled", "keyboardEnabled", Self.modeKey, Self.exceptionStorageKey, Self.quitStorageKey].contains($0)
                || $0.hasPrefix("license.")
        }
        if defaults.object(forKey: Self.onboardingKey) == nil {
            defaults.set(existing, forKey: Self.onboardingKey)
            if defaults.object(forKey: Self.exceptionStorageKey) == nil {
                // 没有已保存列表时一律播种当前默认名单；existing 只用于上面的 onboarding 标记。
                // 已被旧版自动播种过的名单由 upgradeDefaultRulesIfNeeded 一次性提升到这份默认名单。
                defaults.set(try? JSONEncoder().encode(Self.defaultRules), forKey: Self.exceptionStorageKey)
            }
        }

        mode = Self.storedMode(defaults)
        exceptionRules = Self.decodeRules(from: defaults, forKey: Self.exceptionStorageKey, fallback: Self.defaultRules)
        quitRules = Self.decodeRules(from: defaults, forKey: Self.quitStorageKey, fallback: [])
        observeExternalChanges()
    }

    func setMode(_ mode: RuleMode) {
        guard self.mode != mode else { return }
        self.mode = mode
    }

    /// 把当前模式生效的列表恢复为内置默认：排除模式恢复默认例外名单，仅包含模式清空。
    /// 走属性赋值以复用 didSet 的落盘 / onChange / 多实例广播；另一套列表与迁移、授权状态都不动。
    func resetActiveRulesToDefault() {
        switch mode {
        case .allExceptListed:
            exceptionRules = Self.defaultRules
        case .onlyListed:
            quitRules = []
        }
    }

    func addApplication(at url: URL) throws {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier, !bundleID.isEmpty else {
            throw RuleError.missingBundleID
        }
        insert(AppRule(match: .bundleID, value: bundleID))
    }

    func addApplication(bundleID: String) {
        insert(AppRule(match: .bundleID, value: bundleID))
    }

    func remove(_ rule: AppRule) {
        switch mode {
        case .allExceptListed:
            exceptionRules.remove(rule)
        case .onlyListed:
            quitRules.remove(rule)
        }
    }

    /// 收到其他实例的变更通知后只读刷新内存：不写盘、不广播，因此不会触发保存回环。
    func applyRemoteChange() {
        guard !isApplyingRemoteChange else { return }
        let newMode = Self.storedMode(defaults)
        let newExceptionRules = Self.decodeRules(from: defaults, forKey: Self.exceptionStorageKey, fallback: Self.defaultRules)
        let newQuitRules = Self.decodeRules(from: defaults, forKey: Self.quitStorageKey, fallback: [])
        guard newMode != mode || newExceptionRules != exceptionRules || newQuitRules != quitRules else { return }
        isApplyingRemoteChange = true
        defer { isApplyingRemoteChange = false }
        mode = newMode
        exceptionRules = newExceptionRules
        quitRules = newQuitRules
        notifyChange()
    }

    private func insert(_ rule: AppRule) {
        switch mode {
        case .allExceptListed:
            exceptionRules.insert(rule)
        case .onlyListed:
            quitRules.insert(rule)
        }
    }

    private func save(_ rules: Set<AppRule>, forKey key: String) {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: key)
        }
    }

    private func notifyChange() {
        onChange?(policy)
    }

    private static var notificationSource: String { Bundle.main.bundleIdentifier ?? "unbundled" }

    /// 同一 Bundle ID 可能短暂同时有两个实例（权限恢复重启、DMG 副本），
    /// 一个实例写盘后广播，另一个只读刷新，避免它内存里的旧集合在下一次保存时覆盖新数据。
    private func broadcastChange() {
        let userInfo: [String: String] = [Self.notificationSourceKey: Self.notificationSource]
        NotificationCenter.default.post(name: Self.rulesDidChangeNotification, object: nil, userInfo: userInfo)
        DistributedNotificationCenter.default().postNotificationName(
            Self.rulesDidChangeNotification,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    private func observeExternalChanges() {
        let handler: @Sendable (Notification) -> Void = { [weak self] note in
            let source = note.userInfo?[Self.notificationSourceKey] as? String
            Task { @MainActor in
                guard let self, source == Self.notificationSource else { return }
                self.applyRemoteChange()
            }
        }
        localObservers.append(
            NotificationCenter.default.addObserver(
                forName: Self.rulesDidChangeNotification, object: nil, queue: .main, using: handler)
        )
        distributedObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: Self.rulesDidChangeNotification, object: nil, queue: .main, using: handler)
        )
    }

    deinit {
        localObservers.forEach { NotificationCenter.default.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }

    private static func storedMode(_ defaults: UserDefaults) -> RuleMode {
        RuleMode(rawValue: defaults.string(forKey: modeKey) ?? "") ?? .allExceptListed
    }

    /// 一次性的旧域搬迁：标记只写一次。规则列表只在新域为空、或新域列表仍是旧版
    /// onboarding 自动播种的默认列表时导入；非列表键与列表决策解耦，始终「只补 nil」。
    private static func migrateLegacyDomainIfNeeded(defaults: UserDefaults, legacy: UserDefaults?) {
        guard defaults.object(forKey: legacyMigrationMarkerKey) == nil else { return }
        defer { defaults.set(true, forKey: legacyMigrationMarkerKey) }
        guard let legacy else { return }

        // 跑过 1.6.0/1.6.1 的用户，新域 applicationRules 已经被旧 onboarding 播种成默认列表，
        // 只判断「为 nil」会把这批真正丢规则的人全部跳过；播种列表不是用户编辑的数据，可以整体替换。
        let currentRulesObject = defaults.object(forKey: exceptionStorageKey)
        let currentRules = defaults.data(forKey: exceptionStorageKey)
            .flatMap { try? JSONDecoder().decode(Set<AppRule>.self, from: $0) }
        let importsLegacyRules: Bool
        if currentRulesObject == nil {
            importsLegacyRules = true
        } else if let currentRules {
            importsLegacyRules = isHistoricalAutoSeededList(currentRules)
        } else {
            importsLegacyRules = false
        }

        var copied = false

        // 规则列表：新域为空或仍等于播种指纹时整体替换；用户自定义列表保持不动（绝不并集）。
        if importsLegacyRules,
           let data = legacy.data(forKey: exceptionStorageKey),
           (try? JSONDecoder().decode(Set<AppRule>.self, from: data)) != nil {
            // 命中自动播种的默认列表时这里是替换：那份列表不是用户手动编辑出来的。
            defaults.set(data, forKey: exceptionStorageKey)
            copied = true
        }

        // 非列表键与规则列表解耦：新域缺哪个就补哪个，已有值一律不覆盖。
        // 这样在新域重新加回过规则的用户也能找回旧版的键盘关闭 / 主开关 / 反向模式列表。
        if defaults.object(forKey: quitStorageKey) == nil,
           let data = legacy.data(forKey: quitStorageKey),
           (try? JSONDecoder().decode(Set<AppRule>.self, from: data)) != nil {
            defaults.set(data, forKey: quitStorageKey)
            copied = true
        }
        if defaults.object(forKey: modeKey) == nil,
           let raw = legacy.string(forKey: modeKey), let migrated = RuleMode(rawValue: raw) {
            defaults.set(migrated.rawValue, forKey: modeKey)
            copied = true
        }
        if defaults.object(forKey: "enabled") == nil,
           let enabled = legacy.object(forKey: "enabled") as? Bool {
            defaults.set(enabled, forKey: "enabled")
            copied = true
        }
        if defaults.object(forKey: "keyboardEnabled") == nil,
           let keyboardEnabled = legacy.object(forKey: "keyboardEnabled") as? Bool {
            defaults.set(keyboardEnabled, forKey: "keyboardEnabled")
            copied = true
        }
        // 老用户升级后不应再看到新用户引导：旧版播种会把该键写成 false（当成新用户），
        // 这里只要本次真从旧域搬过数据就纠正为 true。
        if copied, !defaults.bool(forKey: onboardingKey) {
            defaults.set(true, forKey: onboardingKey)
        }

        // 1.4.0 才引入本地授权，这批用户当年从未授权过：旧域有使用痕迹就补 Pro。
        // 只挡真实的 license.key 和已有的 legacyPro：跑过 1.6.x 的用户当前域早已写入
        // trialStart / migrated / lastValidatedAt，这些都不能阻断 1.4.0 的自动保留承诺。
        let legacyRules = legacy.data(forKey: exceptionStorageKey)
            .flatMap { try? JSONDecoder().decode(Set<AppRule>.self, from: $0) }
        let legacyHadUsage = legacyRules != nil
            || (legacy.object(forKey: "keyboardEnabled") as? Bool) != nil
            || (legacy.object(forKey: "enabled") as? Bool) != nil
        let currentHasRealKey = defaults.object(forKey: "license.key") != nil
        if legacyHadUsage, !currentHasRealKey, defaults.object(forKey: legacyProKey) == nil {
            defaults.set("1", forKey: legacyProKey)
        }
    }

    /// 列表仍是旧版自动播种的集合（23 / 25 条），说明它从未被用户编辑过。
    private static func isHistoricalAutoSeededList(_ rules: Set<AppRule>) -> Bool {
        historicalAutoSeededRules.contains(rules)
    }

    /// 内置默认名单的一次性升级：只把“旧版自动播种、用户从未编辑过”的列表（23/25 条）
    /// 提升为当前默认名单；用户编辑过的列表（含 58+1、空列表）与解码失败一律不动。
    /// 与旧域迁移的标记相互独立，用 defer 写版本号保证只扫一次。
    private static func upgradeDefaultRulesIfNeeded(defaults: UserDefaults) {
        guard defaults.object(forKey: defaultsRevisionKey) == nil else { return }
        defer { defaults.set(defaultsRevision, forKey: defaultsRevisionKey) }
        guard let data = defaults.data(forKey: exceptionStorageKey),
              let currentRules = try? JSONDecoder().decode(Set<AppRule>.self, from: data),
              let upgraded = upgradedAutoSeededList(currentRules),
              let encoded = try? JSONEncoder().encode(upgraded) else { return }
        defaults.set(encoded, forKey: exceptionStorageKey)
    }

    /// 旧版自动播种列表（23 / 25 条）→ 当前默认名单；用户编辑过的列表返回 nil。
    private static func upgradedAutoSeededList(_ rules: Set<AppRule>) -> Set<AppRule>? {
        historicalAutoSeededRules.contains(rules) ? defaultRules : nil
    }

    /// 解码失败时先把原始 Data 备份到 `<key>.unreadable` 再回退：
    /// 否则下一次编辑会用默认列表整集合覆盖，用户的原始规则就永久丢了。
    private static func decodeRules(from defaults: UserDefaults, forKey key: String, fallback: Set<AppRule>) -> Set<AppRule> {
        guard let data = defaults.data(forKey: key) else { return fallback }
        do {
            return try JSONDecoder().decode(Set<AppRule>.self, from: data)
        } catch {
            let backupKey = unreadableBackupKey(for: key)
            // 只保留第一次的原始数据，后续失败不再覆盖。
            if defaults.data(forKey: backupKey) == nil {
                defaults.set(data, forKey: backupKey)
            }
            logger.error("\(decodeFailureLogMessage(key: key, reason: error.localizedDescription), privacy: .public)")
            return fallback
        }
    }

    static func unreadableBackupKey(for key: String) -> String {
        key + unreadableSuffix
    }

    static func decodeFailureLogMessage(key: String, reason: String) -> String {
        "规则存储 \(key) 解码失败，原始数据已备份到 \(unreadableBackupKey(for: key))：\(reason)"
    }

    enum RuleError: LocalizedError {
        case missingBundleID
        var errorDescription: String? {
            NSLocalizedString("rule.error.missingBundleID", comment: "")
        }
    }
}
