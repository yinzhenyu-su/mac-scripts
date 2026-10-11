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
    var detail: String { match == .bundleID ? value : "按应用名称匹配" }
}

struct CloseDecision {
    enum Action: Equatable {
        case close
        case quit
    }

    static func action(bundleID: String?, applicationName: String?, isStandardWindow: Bool, standardWindowCount: Int?, rules: Set<AppRule>) -> Action {
        guard isStandardWindow, standardWindowCount == 1,
              bundleID != nil || applicationName != nil else { return .close }
        if let bundleID, rules.contains(AppRule(match: .bundleID, value: bundleID)) { return .close }
        if let applicationName, rules.contains(AppRule(match: .applicationName, value: applicationName)) { return .close }
        return .quit
    }

    static func shouldQuitAfterKeyboardClose(initialAction: Action, remainingWindowCount: Int?, remainingVisibleWindowCount: Int?, targetStillRunning: Bool) -> Bool {
        initialAction == .quit && targetStillRunning && (remainingWindowCount == 0 || remainingVisibleWindowCount == 0)
    }
}

@MainActor
final class RuleStore: ObservableObject {
    @Published private(set) var rules: Set<AppRule> {
        didSet {
            if let data = try? JSONEncoder().encode(rules) {
                UserDefaults.standard.set(data, forKey: Self.storageKey)
            }
            onChange?(rules)
        }
    }

    var onChange: ((Set<AppRule>) -> Void)?
    private static let storageKey = "applicationRules"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(Set<AppRule>.self, from: data) {
            rules = saved
        } else {
            rules = Set([
                "com.tencent.xinwei", "com.tencent.qq", "com.tencent.qqmusic",
                "com.spotify.client", "com.apple.Music", "com.meta.Telegram", "md.obsidian"
            ].map { AppRule(match: .bundleID, value: $0) } + [
                "OrbStack", "WeChat", "QQ", "QQMusic", "WeType", "Hammerspoon",
                "Swish", "Bob", "Ice", "PopClip", "Pixelmator Pro", "Sketch",
                "ZeroTier", "ClashX Meta", "v2rayN", "ClashX Pro", "Longshot",
                "BetterTouchTool", "DingTalk", "Finder"
            ].map { AppRule(match: .applicationName, value: $0) })
        }
    }

    func addApplication(at url: URL) throws {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier, !bundleID.isEmpty else {
            throw RuleError.missingBundleID
        }
        rules.insert(AppRule(match: .bundleID, value: bundleID))
    }

    func addApplication(bundleID: String) {
        rules.insert(AppRule(match: .bundleID, value: bundleID))
    }

    func remove(_ rule: AppRule) {
        rules.remove(rule)
    }

    enum RuleError: LocalizedError {
        case missingBundleID
        var errorDescription: String? { "无法读取这个 App 的 Bundle ID。" }
    }
}
