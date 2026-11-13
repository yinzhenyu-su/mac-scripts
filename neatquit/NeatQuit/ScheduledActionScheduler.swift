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

    /// 可注入的时钟，默认取系统时间。
    var now: () -> Date

    /// 已发起执行、等待复查的条目。
    private var pendingVerification: [UUID: Date] = [:]
    private var assertions: [UUID: AnyObject] = [:]

    init(
        store: ScheduledActionStore,
        now: @escaping () -> Date = Date.init,
        isAvailable: @escaping (ScheduledAction) -> Bool,
        isStillPresent: @escaping (ScheduledAction) -> Bool,
        perform: @escaping (ScheduledAction, @escaping (Bool) -> Void) -> Void,
        beginPowerAssertion: @escaping (String) -> AnyObject? = { _ in nil },
        endPowerAssertion: @escaping (AnyObject?) -> Void = { _ in }
    ) {
        self.store = store
        self.now = now
        self.isAvailable = isAvailable
        self.isStillPresent = isStillPresent
        self.perform = perform
        self.beginPowerAssertion = beginPowerAssertion
        self.endPowerAssertion = endPowerAssertion
    }

    // MARK: - 对外操作

    func add(target: ScheduleTarget, displayName: String, duration: TimeInterval) {
        store.add(target: target, displayName: displayName, duration: duration, now: now())
    }

    func cancel(id: UUID) {
        store.cancel(id: id)
        pendingVerification.removeValue(forKey: id)
        releaseAssertion(id)
    }

    func cancelAll() {
        store.cancelAll()
        pendingVerification.removeAll()
        for id in assertions.keys { releaseAssertion(id) }
    }

    func retry(id: UUID) {
        guard let action = store.actions.first(where: { $0.id == id }) else { return }
        guard isAvailable(action) else {
            store.remove(id: id)
            return
        }
        attempt(action)
    }

    // MARK: - 周期执行

    func tick() {
        verifyPending()

        for action in store.actions where action.state == .armed {
            // 目标已消失（应用退出 / 磁盘卸载），任务直接移除。
            guard isAvailable(action) else {
                store.remove(id: action.id)
                continue
            }
            switch ScheduleDecision.outcome(fireAt: action.fireAt, now: now()) {
            case .waiting:
                continue
            case .fire:
                attempt(action)
            case .expired:
                logger.info("dropped expired action: target=\(action.target.identifier, privacy: .public)")
                store.remove(id: action.id)
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
                } else if self.isStillPresent(action) {
                    self.store.markRefused(id: action.id)
                    self.releaseAssertion(action.id)
                } else {
                    self.store.remove(id: action.id)
                    self.releaseAssertion(action.id)
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
                store.markRefused(id: id)
            } else {
                logger.info("perform completed: target=\(action.target.identifier, privacy: .public)")
                store.remove(id: id)
            }
        }
    }

    private func releaseAssertion(_ id: UUID) {
        guard let token = assertions.removeValue(forKey: id) else { return }
        endPowerAssertion(token)
    }
}
