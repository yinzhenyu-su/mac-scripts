import AppKit
import Combine

struct AppRule: Codable, Hashable, Identifiable {
    enum Match: String, Codable {
        case bundleID
        case applicationName
    }

    let match: Match
    let value: String

    var id: String { "\(match.rawValue):\(value)" }
    var displayName: String { match == .bundleID ? (NSWorkspace.shared.urlForApplication(withBundleIdentifier: value)?.deletingPathExtension().lastPathComponent ?? value) : value }
    var detail: String {
        match == .bundleID ? value : NSLocalizedString("rule.detail.applicationName", comment: "")
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

@MainActor
final class RuleStore: ObservableObject {
    @Published private(set) var mode: RuleMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
            notifyChange()
        }
    }

    @Published private(set) var exceptionRules: Set<AppRule> {
        didSet {
            save(exceptionRules, forKey: Self.exceptionStorageKey)
            notifyChange()
        }
    }

    @Published private(set) var quitRules: Set<AppRule> {
        didSet {
            save(quitRules, forKey: Self.quitStorageKey)
            notifyChange()
        }
    }

    var onChange: ((RulePolicy) -> Void)?
    private static let modeKey = "ruleMode"
    private static let exceptionStorageKey = "applicationRules"
    private static let quitStorageKey = "applicationQuitRules"

    var activeRules: Set<AppRule> {
        mode == .allExceptListed ? exceptionRules : quitRules
    }

    var policy: RulePolicy {
        RulePolicy(mode: mode, rules: activeRules)
    }

    init() {
        mode = RuleMode(rawValue: UserDefaults.standard.string(forKey: Self.modeKey) ?? "") ?? .allExceptListed

        if let data = UserDefaults.standard.data(forKey: Self.exceptionStorageKey),
           let saved = try? JSONDecoder().decode(Set<AppRule>.self, from: data) {
            exceptionRules = saved
        } else {
            exceptionRules = Set([
                "com.tencent.xinWeChat", "com.tencent.qq", "com.tencent.qqmusic",
                "com.spotify.client", "com.apple.Music", "com.meta.Telegram",
                "com.netease.163music",
            ].map { AppRule(match: .bundleID, value: $0) } + [
                "OrbStack", "QQ", "QQMusic", "WeType", "Hammerspoon",
                "Swish", "Bob", "Ice", "PopClip",
                "ZeroTier", "ClashX Meta", "v2rayN", "ClashX Pro", "Longshot",
                "BetterTouchTool", "DingTalk",
            ].map { AppRule(match: .applicationName, value: $0) })
        }

        if let data = UserDefaults.standard.data(forKey: Self.quitStorageKey),
           let saved = try? JSONDecoder().decode(Set<AppRule>.self, from: data) {
            quitRules = saved
        } else {
            quitRules = []
        }
    }

    func setMode(_ mode: RuleMode) {
        guard self.mode != mode else { return }
        self.mode = mode
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
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func notifyChange() {
        onChange?(policy)
    }

    enum RuleError: LocalizedError {
        case missingBundleID
        var errorDescription: String? {
            NSLocalizedString("rule.error.missingBundleID", comment: "")
        }
    }
}
