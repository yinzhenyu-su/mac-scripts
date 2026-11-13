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

/// 一次性的定时任务。只有 `armed` 会被持久化。
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
    var fireAt: Date
    var state: State

    init(
        id: UUID = UUID(),
        target: ScheduleTarget,
        displayName: String,
        fireAt: Date,
        state: State = .armed
    ) {
        self.id = id
        self.target = target
        self.displayName = displayName
        self.fireAt = fireAt
        self.state = state
    }
}

/// 定时任务的判定逻辑，保持为纯函数以便直接回归测试。
enum ScheduleDecision {
    enum Outcome: Equatable {
        case waiting
        case fire
        case expired
    }

    /// 超过计划时刻 5 分钟内补跑，超过则丢弃。
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
