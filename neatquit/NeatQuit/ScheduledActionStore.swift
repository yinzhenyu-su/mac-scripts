import Combine
import Foundation

/// 定时任务的持久化层。只有 `armed` 条目会被写入磁盘。
/// 首次启动时把旧的 `schedule.timers`（仅应用目标）迁移到 `schedule.actions`。
@MainActor
final class ScheduledActionStore: ObservableObject {
    @Published private(set) var actions: [ScheduledAction] = []

    var onChange: (([ScheduledAction]) -> Void)?

    static let storageKey = "schedule.actions"
    static let legacyStorageKey = "schedule.timers"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateLegacyIfNeeded()
        guard let data = defaults.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([ScheduledAction].self, from: data) else { return }
        var seen = Set<String>()
        actions = saved
            .filter { $0.state == .armed }
            .filter { seen.insert($0.target.identifier).inserted }
    }

    // MARK: - 变更

    func add(
        target: ScheduleTarget,
        displayName: String,
        duration: TimeInterval,
        now: Date = Date(),
        mode: ScheduleMode = .timed
    ) {
        guard duration > 0 else { return }
        // 同一目标再设一次视为覆盖，不叠加；切换方式也走这里。
        actions.removeAll { $0.target.identifier == target.identifier }
        actions.append(ScheduledAction(
            target: target,
            displayName: displayName,
            fireAt: now.addingTimeInterval(duration),
            mode: mode,
            idleSeconds: mode == .idle ? duration : nil
        ))
        persist()
        notify()
    }

    /// 闲置规则检测到读写或失败顺延时刷新下一次触发时刻。
    /// 这是高频运行时状态：不落盘，也不触发菜单重建，菜单的 1 秒计时器会直接读到新值。
    func resetIdleStart(id: UUID, seconds: TimeInterval, now: Date) {
        guard seconds > 0,
              let index = actions.firstIndex(where: { $0.id == id }) else { return }
        // 失败顺延会把条目从 firing 拉回 armed；firing 不落盘，这里必须补写，
        // 否则重启后规则会丢失。活动重置时条目本来就是 armed，无需重复写盘。
        let wasFiring = actions[index].state == .firing
        actions[index].fireAt = now.addingTimeInterval(seconds)
        actions[index].state = .armed
        if wasFiring { persist() }
    }

    func cancel(id: UUID) {
        guard actions.contains(where: { $0.id == id }) else { return }
        actions.removeAll { $0.id == id }
        persist()
        notify()
    }

    func cancelAll() {
        guard !actions.isEmpty else { return }
        actions.removeAll()
        persist()
        notify()
    }

    func markFiring(id: UUID) {
        update(id) { $0.state = .firing }
    }

    func markRefused(id: UUID) {
        update(id) { $0.state = .refused }
    }

    func remove(id: UUID) {
        cancel(id: id)
    }

    /// 目标已经不存在（应用退出 / 磁盘卸载）时移除对应任务。
    func remove(identifier: String) {
        guard actions.contains(where: { $0.target.identifier == identifier }) else { return }
        actions.removeAll { $0.target.identifier == identifier }
        persist()
        notify()
    }

    // MARK: - 内部

    private func update(_ id: UUID, _ transform: (inout ScheduledAction) -> Void) {
        guard let index = actions.firstIndex(where: { $0.id == id }) else { return }
        transform(&actions[index])
        persist()
        notify()
    }

    private func persist() {
        let armed = actions.filter { $0.state == .armed }
        if armed.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else if let data = try? JSONEncoder().encode(armed) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func notify() {
        onChange?(actions)
    }

    private func migrateLegacyIfNeeded() {
        guard defaults.data(forKey: Self.storageKey) == nil,
              let data = defaults.data(forKey: Self.legacyStorageKey) else { return }
        guard let legacy = try? JSONDecoder().decode([LegacyQuitTimer].self, from: data) else { return }
        let migrated = legacy
            .filter { $0.state == ScheduledAction.State.armed.rawValue }
            .map {
                ScheduledAction(
                    id: $0.id,
                    target: .application($0.bundleID),
                    displayName: $0.displayName,
                    fireAt: $0.fireAt
                )
            }
        guard let encoded = try? JSONEncoder().encode(migrated) else { return }
        defaults.set(encoded, forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.legacyStorageKey)
    }

    private struct LegacyQuitTimer: Codable {
        let id: UUID
        let bundleID: String
        let displayName: String
        let fireAt: Date
        let state: String
    }
}
