import AppKit
import Combine
import Foundation

/// 许可证状态与 Creem 授权流程。密钥只保存在本机偏好设置，校验由 bgm.fun 的
/// /license-api/ 代理完成，Creem API key 不会进入客户端。
@MainActor
final class LicenseManager: ObservableObject {
    enum Tier: Equatable {
        case free
        case trial(daysLeft: Int)
        case pro
    }

    @Published private(set) var tier: Tier = .free {
        didSet {
            guard oldValue != tier else { return }
            onChange?(tier)
        }
    }
    @Published private(set) var licenseKey: String?
    @Published private(set) var activationCount: Int?
    @Published private(set) var activationLimit: Int?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false

    var onChange: ((Tier) -> Void)?

    var hasPro: Bool { tier == .pro }
    /// 试用期同样解锁 Pro 功能。
    var isEntitled: Bool {
        switch tier {
        case .pro, .trial: return true
        case .free: return false
        }
    }
    var canManageLicense: Bool { licenseKey != nil }

    static let shared = LicenseManager()
    static let purchaseURL = URL(string: "https://bgm.fun/neatquit/#pricing")!
    static let trialDays = 7

    private let trialAccount = "license.trialStart"
    private let keyAccount = "license.key"
    private let instanceAccount = "license.instance"
    private let legacyAccount = "license.legacyPro"
    private let migrationAccount = "license.migrated"
    private let apiBaseKey = "license.apiBase"
    private let trialDaysKey = "license.trialDays"

    private var apiBase: URL {
        if let override = UserDefaults.standard.string(forKey: apiBaseKey), let url = URL(string: override) {
            return url
        }
        return URL(string: "https://bgm.fun/license-api")!
    }

    private init() {
        licenseKey = LocalStore.read(keyAccount)
        migrateLegacyUsageIfNeeded()
        loadTier()
    }

    // MARK: - 启动校验

    func validateOnLaunch() async {
        guard LocalStore.read(instanceAccount) != nil || licenseKey != nil else { return }
        await refresh(force: false)
    }

    // MARK: - 激活 / 校验 / 移除

    func activate(input: String) async {
        let key = Self.normalize(input)
        guard Self.isValidKeyFormat(key) else {
            errorMessage = L10n.licenseErrorFormat
            return
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let response = try await post("activate", body: [
                "key": key,
                "instanceName": Self.deviceName(),
            ])
            guard let instanceId = response.instanceId else {
                errorMessage = L10n.licenseErrorGeneric
                return
            }
            LocalStore.write(key, account: keyAccount)
            LocalStore.write(instanceId, account: instanceAccount)
            licenseKey = key
            apply(response)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func refresh(force: Bool) async {
        guard let key = licenseKey else { return }
        guard let instanceId = LocalStore.read(instanceAccount) else { return }
        guard force || shouldValidateNow() else { return }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let response = try await post("validate", body: [
                "key": key,
                "instanceId": instanceId,
            ])
            apply(response)
        } catch {
            // 网络错误时保留现有状态，避免离线用户被误降级。
            if case LicenseAPIError.http(_, let code) = error {
                if code == "invalid_license" || code == "license_expired" {
                    tier = .free
                    errorMessage = Self.message(for: error)
                } else {
                    errorMessage = Self.message(for: error)
                }
            }
        }
    }

    func deactivate() async {
        guard let key = licenseKey, let instanceId = LocalStore.read(instanceAccount) else { return }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            _ = try await post("deactivate", body: ["key": key, "instanceId": instanceId])
        } catch {
            // 即使服务端失败也清除本地状态，用户可重新激活。
            errorMessage = Self.message(for: error)
        }

        LocalStore.delete(keyAccount)
        LocalStore.delete(instanceAccount)
        licenseKey = nil
        activationCount = nil
        activationLimit = nil
        loadTier()
    }

    // MARK: - 状态

    private func apply(_ response: LicenseResponse) {
        activationCount = response.activation
        activationLimit = response.activationLimit

        switch response.status {
        case "active":
            tier = .pro
            errorMessage = nil
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "license.lastValidatedAt")
        case "inactive":
            tier = .free
            errorMessage = L10n.licenseErrorInactive
        case "expired":
            tier = .free
            errorMessage = L10n.licenseErrorExpired
        case "disabled":
            tier = .free
            errorMessage = L10n.licenseErrorDisabled
        default:
            tier = .free
            errorMessage = L10n.licenseErrorGeneric
        }
    }

    private func loadTier() {
        if LocalStore.read(legacyAccount) == "1" {
            tier = .pro
            return
        }
        if licenseKey != nil {
            // 先按已授权显示，联网校验失败再降级。
            tier = .pro
            return
        }

        let formatter = ISO8601DateFormatter()
        let start: Date
        if let raw = LocalStore.read(trialAccount), let saved = formatter.date(from: raw) {
            start = saved
        } else {
            start = Date()
            LocalStore.write(formatter.string(from: start), account: trialAccount)
        }

        let elapsed = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        let left = max(0, effectiveTrialDays - elapsed)
        tier = left > 0 ? .trial(daysLeft: left) : .free
    }

    /// 服务端可调整试用天数；失败时沿用本地缓存或默认值。
    private var effectiveTrialDays: Int {
        let cached = UserDefaults.standard.integer(forKey: trialDaysKey)
        return cached > 0 ? cached : Self.trialDays
    }

    func refreshConfiguration() async {
        do {
            let (data, response) = try await URLSession.shared.data(
                from: apiBase.appendingPathComponent("config"))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let config = try JSONDecoder().decode(RemoteConfig.self, from: data)
            guard let days = config.trialDays, days > 0 else { return }
            let previous = UserDefaults.standard.integer(forKey: trialDaysKey)
            UserDefaults.standard.set(days, forKey: trialDaysKey)
            if previous != days { loadTier() }
        } catch {
            // 网络失败时保留本地缓存
        }
    }

    private func shouldValidateNow() -> Bool {
        let last = UserDefaults.standard.double(forKey: "license.lastValidatedAt")
        guard last > 0 else { return true }
        return Date().timeIntervalSince1970 - last > 24 * 60 * 60
    }

    /// 1.4.0 首次启动时识别已有的免费用户：只要用过 ⌘W、例外列表或主开关，
    /// 就保留 PRO 权限，避免升级后功能被收回。
    private func migrateLegacyUsageIfNeeded() {
        guard LocalStore.read(migrationAccount) != "1" else { return }
        LocalStore.write("1", account: migrationAccount)

        let defaults = UserDefaults.standard
        let usedBefore = (defaults.object(forKey: "rules.legacyUsageSnapshot") as? Bool)
            ?? (defaults.object(forKey: "keyboardEnabled") != nil
                || defaults.object(forKey: "applicationRules") != nil
                || defaults.object(forKey: "enabled") != nil)
        if usedBefore {
            LocalStore.write("1", account: legacyAccount)
        }
    }

    // MARK: - 网络

    private func post(_ path: String, body: [String: String]) async throws -> LicenseResponse {
        var request = URLRequest(url: apiBase.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LicenseAPIError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw LicenseAPIError.malformed
        }
        if http.statusCode == 200 {
            guard let decoded = try? JSONDecoder().decode(LicenseResponse.self, from: data) else {
                throw LicenseAPIError.malformed
            }
            return decoded
        }

        let code = (try? JSONDecoder().decode(APIError.self, from: data))?.error ?? "unknown"
        throw LicenseAPIError.http(http.statusCode, code)
    }

    private static func message(for error: Error) -> String {
        guard case LicenseAPIError.http(_, let code) = error else {
            return L10n.licenseErrorNetwork
        }
        switch code {
        case "invalid_key_format": return L10n.licenseErrorFormat
        case "invalid_license": return L10n.licenseErrorInvalid
        case "activation_limit": return L10n.licenseErrorLimit
        case "license_expired": return L10n.licenseErrorExpired
        case "rate_limited": return L10n.licenseErrorRate
        default: return L10n.licenseErrorGeneric
        }
    }

    // MARK: - 工具

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
    }

    static func isValidKeyFormat(_ key: String) -> Bool {
        key.range(of: #"^[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}$"#, options: .regularExpression) != nil
    }

    private static func deviceName() -> String {
        let name = Host.current().localizedName ?? "Mac"
        return String(name.prefix(80))
    }
}

private struct RemoteConfig: Decodable {
    let trialDays: Int?
    let activationLimit: Int?
}

private struct LicenseResponse: Decodable {
    let status: String
    let licenseId: String?
    let instanceId: String?
    let activation: Int?
    let activationLimit: Int?
    let expiresAt: String?
}

private struct APIError: Decodable {
    let error: String
}

enum LicenseAPIError: Error {
    case http(Int, String)
    case offline
    case malformed
}

private enum LocalStore {
    static func read(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func write(_ value: String, account: String) {
        UserDefaults.standard.set(value, forKey: account)
    }

    static func delete(_ account: String) {
        UserDefaults.standard.removeObject(forKey: account)
    }
}
