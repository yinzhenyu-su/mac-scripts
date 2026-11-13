import Foundation
import OSLog

/// 定时任务的调度器。时间判定委托给 `ScheduleDecision`，
/// 与 AppKit / DiskArbitration 的耦合全部通过注入闭包完成。
@MainActor
final class ScheduledActionScheduler {
    private let logger = Logger(subsystem: "fun.bgm.neatquit", category: "ScheduledActionScheduler")
    private let store: ScheduledActionStore
    private let isAvailable: (ScheduledAction) -> Bool
    private let isStillPresent: (ScheduledAction) -> Bool
    private let perform: (ScheduledAction, @escaping (Bool) -> Void) -> Void
    private let beginPowerAssertion: (String) -> AnyObject?
    private let endPowerAssertion: (AnyObject?) -> Void
    /// 闲置规则的活动探测。没有注入时视为始终有活动，避免误弹。
    private let isActive: (ScheduledAction) -> Bool

    /// 可注入的时钟，默认取系统时间。
    var now: () -> Date

    /// 已发起执行、等待复查的条目。
    private var pendingVerification: [UUID: Date] = [:]
    private var assertions: [UUID: AnyObject] = [:]
    /// 闲置规则的连续失败次数；检测到读写时清零。
    private var idleFailures: [UUID: Int] = [:]
    private var lastTick: Date?

    /// 同一闲置规则连续失败达到该次数后转为「未弹出」，避免无声地无限重试。
    static let idleFailureLimit = 3

    init(
        store: ScheduledActionStore,
        now: @escaping () -> Date = Date.init,
        isAvailable: @escaping (ScheduledAction) -> Bool,
        isStillPresent: @escaping (ScheduledAction) -> Bool,
        perform: @escaping (ScheduledAction, @escaping (Bool) -> Void) -> Void,
        isActive: @escaping (ScheduledAction) -> Bool = { _ in true },
        beginPowerAssertion: @escaping (String) -> AnyObject? = { _ in nil },
        endPowerAssertion: @escaping (AnyObject?) -> Void = { _ in }
    ) {
        self.store = store
        self.now = now
        self.isAvailable = isAvailable
        self.isStillPresent = isStillPresent
        self.perform = perform
        self.isActive = isActive
        self.beginPowerAssertion = beginPowerAssertion
        self.endPowerAssertion = endPowerAssertion
        resetIdleStarts(now: now())
    }

    // MARK: - 对外操作

    func add(
        target: ScheduleTarget,
        displayName: String,
        duration: TimeInterval,
        mode: ScheduleMode = .timed
    ) {
        store.add(target: target, displayName: displayName, duration: duration, now: now(), mode: mode)
    }

    func cancel(id: UUID) {
        store.cancel(id: id)
        pendingVerification.removeValue(forKey: id)
        idleFailures.removeValue(forKey: id)
        releaseAssertion(id)
    }

    func cancelAll() {
        store.cancelAll()
        pendingVerification.removeAll()
        idleFailures.removeAll()
        for id in assertions.keys { releaseAssertion(id) }
    }

    func retry(id: UUID) {
        guard let action = store.actions.first(where: { $0.id == id }) else { return }
        guard isAvailable(action) else {
            store.remove(id: id)
            return
        }
        // 用户明确重试，重新给满失败次数。
        idleFailures[id] = 0
        attempt(action)
    }

    /// 启动、唤醒或长时间挂起后，把所有闲置规则的起点重置为当前时刻。
    func resetIdleStarts(now: Date) {
        for action in store.actions where action.mode == .idle && action.state == .armed {
            guard let seconds = action.idleSeconds else { continue }
            store.resetIdleStart(id: action.id, seconds: seconds, now: now)
        }
    }

    // MARK: - 周期执行

    func tick() {
        let current = now()
        // 睡眠期间定时器不触发；恢复后第一次 tick 的间隔会很大，视为唤醒边界。
        if let lastTick, current.timeIntervalSince(lastTick) > 60 {
            resetIdleStarts(now: current)
        }
        lastTick = current

        verifyPending()

        for action in store.actions where action.state == .armed {
            // 目标已消失（应用退出 / 磁盘卸载），任务直接移除。
            guard isAvailable(action) else {
                store.remove(id: action.id)
                idleFailures.removeValue(forKey: action.id)
                continue
            }

            if action.mode == .idle {
                if isActive(action) {
                    idleFailures[action.id] = 0
                    if let seconds = action.idleSeconds {
                        store.resetIdleStart(id: action.id, seconds: seconds, now: current)
                    }
                    continue
                }
            }

            switch ScheduleDecision.outcome(for: action, now: current) {
            case .waiting:
                continue
            case .fire:
                attempt(action)
            case .expired:
                logger.info("dropped expired action: target=\(action.target.identifier, privacy: .public)")
                store.remove(id: action.id)
                idleFailures.removeValue(forKey: action.id)
            }
        }
    }

    // MARK: - 内部

    private func attempt(_ action: ScheduledAction) {
        store.markFiring(id: action.id)
        assertions[action.id] = beginPowerAssertion(action.displayName)
        perform(action) { [weak self] accepted in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.logger.info(
                    "perform requested: target=\(action.target.identifier, privacy: .public) accepted=\(accepted, privacy: .public)"
                )
                if accepted {
                    self.pendingVerification[action.id] = self.now()
                } else {
                    self.handleFailure(action)
                }
            }
        }
    }

    /// 执行接口返回的是"请求已被接受"，因此要延迟复查目标是否真的消失。
    private func verifyPending() {
        let current = now()
        let due = pendingVerification.filter {
            current.timeIntervalSince($0.value) >= ScheduleDecision.verificationDelay
        }
        for (id, _) in due {
            pendingVerification.removeValue(forKey: id)
            defer { releaseAssertion(id) }

            guard let action = store.actions.first(where: { $0.id == id }) else { continue }
            if isStillPresent(action) {
                logger.info("perform refused: target=\(action.target.identifier, privacy: .public)")
                handleFailure(action)
            } else {
                logger.info("perform completed: target=\(action.target.identifier, privacy: .public)")
                store.remove(id: id)
                idleFailures.removeValue(forKey: id)
            }
        }
    }

    /// 倒计时失败立即标记未弹出；闲置失败先当作「仍在使用」顺延，
    /// 连续失败达到上限才标记，避免播放视频等场景产生噪声。
    private func handleFailure(_ action: ScheduledAction) {
        guard isStillPresent(action) else {
            store.remove(id: action.id)
            idleFailures.removeValue(forKey: action.id)
            releaseAssertion(action.id)
            return
        }

        guard action.mode == .idle, let seconds = action.idleSeconds else {
            store.markRefused(id: action.id)
            releaseAssertion(action.id)
            return
        }

        let failures = (idleFailures[action.id] ?? 0) + 1
        idleFailures[action.id] = failures
        if failures >= Self.idleFailureLimit {
            store.markRefused(id: action.id)
        } else {
            store.resetIdleStart(id: action.id, seconds: seconds, now: now())
        }
        releaseAssertion(action.id)
    }

    private func releaseAssertion(_ id: UUID) {
        guard let token = assertions.removeValue(forKey: id) else { return }
        endPowerAssertion(token)
    }
}
