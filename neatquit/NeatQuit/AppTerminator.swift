import AppKit
import IOKit.pwr_mgt

/// 全应用唯一的退出入口：关窗退出与定时退出都必须走这里，
/// 保证两者在"如何退"上永远一致（正常退出、不强杀）。
enum AppTerminator {
    static func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    @discardableResult
    static func quit(bundleID: String) -> Bool {
        guard let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first else { return false }
        return quit(application)
    }

    @discardableResult
    static func quit(_ application: NSRunningApplication) -> Bool {
        application.terminate()
    }
}

/// 触发瞬间的短命断言：只覆盖退出请求与结果复查，
/// 倒计时期间不持有任何阻止系统睡眠的断言。
enum PowerAssertion {
    static func begin(reason: String) -> AnyObject? {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Neat Quit: \(reason)" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return nil }
        return NSNumber(value: id)
    }

    static func end(_ token: AnyObject?) {
        guard let id = (token as? NSNumber)?.uint32Value else { return }
        IOPMAssertionRelease(IOPMAssertionID(id))
    }
}
