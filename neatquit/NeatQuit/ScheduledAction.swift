import Foundation

/// 定时任务的目标。应用用 bundle identifier，磁盘用主卷路径；
/// 整盘 BSD 名只在磁盘目标上使用，用于触发后复查设备是否仍在。
struct ScheduleTarget: Codable, Equatable {
    enum Kind: String, Codable {
        case application
        case disk
    }

    let kind: Kind
    let identifier: String
    var diskBSDName: String?

    static func application(_ bundleID: String) -> ScheduleTarget {
        ScheduleTarget(kind: .application, identifier: bundleID, diskBSDName: nil)
    }

    static func disk(mainVolumePath: String, bsdName: String?) -> ScheduleTarget {
        ScheduleTarget(kind: .disk, identifier: mainVolumePath, diskBSDName: bsdName)
    }

    var bundleID: String? { kind == .application ? identifier : nil }
    var mainVolumePath: String? { kind == .disk ? identifier : nil }
}

/// 磁盘弹出规则的触发方式。
enum ScheduleMode: String, Codable {
    /// 到点触发，`fireAt` 是绝对时刻。
    case timed
    /// 连续无读写达到阈值后触发，`fireAt` 是「闲置起点 + 阈值」的派生值。
    case idle
}

/// 一次性的弹出 / 退出任务。只有 `armed` 会被持久化。
struct ScheduledAction: Codable, Equatable, Identifiable {
    enum State: String, Codable {
        /// 正常倒计时中，写入偏好设置。
        case armed
        /// 已发起执行，等待复查结果，仅存于内存。
        case firing
        /// 目标拒绝了执行（应用未退出 / 磁盘未弹出），仅存于内存。
        case refused
    }

    let id: UUID
    var target: ScheduleTarget
    let displayName: String
    /// 下一次应当触发的时刻。倒计时为创建时算出的绝对时刻；
    /// 闲置模式由调度器在每次检测到读写时重新计算，不依赖持久化的历史值。
    var fireAt: Date
    var mode: ScheduleMode
    /// 闲置模式的阈值秒数；倒计时模式为 nil。
    var idleSeconds: TimeInterval?
    var state: State

    init(
        id: UUID = UUID(),
        target: ScheduleTarget,
        displayName: String,
        fireAt: Date,
        state: State = .armed,
        mode: ScheduleMode = .timed,
        idleSeconds: TimeInterval? = nil
    ) {
        self.id = id
        self.target = target
        self.displayName = displayName
        self.fireAt = fireAt
        self.state = state
        self.mode = mode
        self.idleSeconds = idleSeconds
    }

    /// 闲置规则的阈值分钟数，用于菜单与面板文案。
    var idleMinutes: Int? {
        guard mode == .idle, let idleSeconds else { return nil }
        return max(1, Int(idleSeconds / 60))
    }

    // 旧记录只有 fireAt，没有 mode / idleSeconds：按倒计时读取。
    private enum CodingKeys: String, CodingKey {
        case id, target, displayName, fireAt, mode, idleSeconds, state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        target = try container.decode(ScheduleTarget.self, forKey: .target)
        displayName = try container.decode(String.self, forKey: .displayName)
        fireAt = try container.decode(Date.self, forKey: .fireAt)
        mode = try container.decodeIfPresent(ScheduleMode.self, forKey: .mode) ?? .timed
        idleSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .idleSeconds)
        state = try container.decodeIfPresent(State.self, forKey: .state) ?? .armed
    }
}

/// 定时任务的判定逻辑，保持为纯函数以便直接回归测试。
enum ScheduleDecision {
    enum Outcome: Equatable {
        case waiting
        case fire
        case expired
    }

    /// 超过计划时刻 5 分钟内补跑，超过则丢弃。只适用于倒计时。
    static let overdueWindow: TimeInterval = 5 * 60

    /// 复查执行结果的等待时长。
    static let verificationDelay: TimeInterval = 2.5

    static func outcome(
        fireAt: Date,
        now: Date,
        window: TimeInterval = overdueWindow
    ) -> Outcome {
        let overdue = now.timeIntervalSince(fireAt)
        if overdue < 0 { return .waiting }
        if overdue <= window { return .fire }
        return .expired
    }

    /// 闲置规则没有过期窗口：只要还没到阈值就继续等待，到了就触发。
    static func outcome(for action: ScheduledAction, now: Date) -> Outcome {
        switch action.mode {
        case .timed:
            return outcome(fireAt: action.fireAt, now: now)
        case .idle:
            return now >= action.fireAt ? .fire : .waiting
        }
    }

    static func isDue(fireAt: Date, now: Date) -> Bool {
        outcome(fireAt: fireAt, now: now) == .fire
    }

    static func isStale(fireAt: Date, now: Date, window: TimeInterval = overdueWindow) -> Bool {
        outcome(fireAt: fireAt, now: now, window: window) == .expired
    }

    /// `29:41` 或 `1:12:00`；已到期或已超时统一返回 `0:00`。
    static func remainingText(fireAt: Date, now: Date) -> String {
        let remaining = fireAt.timeIntervalSince(now)
        let total = max(0, Int(remaining.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// 按剩余时间升序，同一时刻按名称稳定排序。
    static func ordered(_ actions: [ScheduledAction]) -> [ScheduledAction] {
        actions.sorted {
            if $0.fireAt != $1.fireAt { return $0.fireAt < $1.fireAt }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    /// 某一类目标中最早到期的任务；没有时返回 nil。
    static func earliest(
        _ actions: [ScheduledAction],
        kind: ScheduleTarget.Kind
    ) -> ScheduledAction? {
        ordered(actions.filter { $0.target.kind == kind && $0.state == .armed }).first
    }

    /// 菜单入口行展示的最早到期剩余时间；该类目标没有任务时返回 nil。
    static func topLevelSuffix(
        _ actions: [ScheduledAction],
        kind: ScheduleTarget.Kind,
        now: Date
    ) -> String? {
        guard let earliest = earliest(actions, kind: kind) else { return nil }
        return remainingText(fireAt: earliest.fireAt, now: now)
    }
}
