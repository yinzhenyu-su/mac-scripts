import Foundation
import IOKit

/// 按整盘读取累计读写计数，用相邻采样的增量判断「最近有没有读写」。
/// 只在存在闲置规则时被调用；解析出的驱动条目会缓存，磁盘消失后自动重新解析。
final class DiskActivityMonitor {
    struct Counters: Equatable {
        var bytes: UInt64
        var ops: UInt64
    }

    private var drivers: [String: io_registry_entry_t] = [:]
    private var lastCounters: [String: Counters] = [:]
    private var lastActivityAt: [String: Date] = [:]

    deinit {
        for (_, driver) in drivers {
            IOObjectRelease(driver)
        }
    }

    /// 该磁盘自上次采样以来是否发生过读写。
    /// 读不到计数时按「有活动」处理：宁可永不触发，也不在状态未知时弹盘。
    func hasActivity(bsdName: String, now: Date = Date()) -> Bool {
        guard let current = readCounters(bsdName: bsdName) else {
            lastActivityAt[bsdName] = now
            return true
        }
        defer { lastCounters[bsdName] = current }
        guard let previous = lastCounters[bsdName] else {
            // 第一次采样只建立基线。
            return false
        }
        let active = current.bytes != previous.bytes || current.ops != previous.ops
        if active { lastActivityAt[bsdName] = now }
        return active
    }

    /// 菜单用：最近一次采样是否刚检测到读写。只读状态，不消耗采样。
    func isRecentlyActive(bsdName: String?, now: Date = Date(), window: TimeInterval = 8) -> Bool {
        guard let bsdName, let last = lastActivityAt[bsdName] else { return false }
        return now.timeIntervalSince(last) <= window
    }

    /// 面板用：该磁盘能否提供读写计数，决定闲置选项是否可用。
    func supportsActivity(bsdName: String) -> Bool {
        readCounters(bsdName: bsdName) != nil
    }

    /// 规则被取消或磁盘移除后清掉缓存，避免 registry 条目泄漏。
    func forget(bsdName: String) {
        if let driver = drivers.removeValue(forKey: bsdName) {
            IOObjectRelease(driver)
        }
        lastCounters.removeValue(forKey: bsdName)
        lastActivityAt.removeValue(forKey: bsdName)
    }

    // MARK: - 内部

    private func readCounters(bsdName: String) -> Counters? {
        if let driver = drivers[bsdName], let counters = Self.counters(driver) {
            return counters
        }
        // 缓存的条目已失效（磁盘拔出 / 驱动重建），释放后重新解析一次。
        if let stale = drivers.removeValue(forKey: bsdName) {
            IOObjectRelease(stale)
        }
        guard let driver = Self.findDriver(bsdName: bsdName) else { return nil }
        drivers[bsdName] = driver
        return Self.counters(driver)
    }

    private static func findDriver(bsdName: String) -> io_registry_entry_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOMedia"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var media = IOIteratorNext(iterator)
        while media != 0 {
            // 用 let 捕获当前条目：defer 在循环体结束时执行，此时 media 已被重新赋值。
            let currentMedia = media
            defer { IOObjectRelease(currentMedia) }

            let name = IORegistryEntryCreateCFProperty(
                currentMedia,
                "BSD Name" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? String

            if name == bsdName {
                return driverEntry(from: currentMedia)
            }
            media = IOIteratorNext(iterator)
        }
        return nil
    }

    /// 从 IOMedia 向上找到 IOBlockStorageDriver；返回前 retain，交给调用方释放。
    private static func driverEntry(from media: io_registry_entry_t) -> io_registry_entry_t? {
        var current = media
        var owned: [io_registry_entry_t] = []
        defer { for entry in owned { IOObjectRelease(entry) } }

        for _ in 0..<10 {
            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(current, &className)
            if String(cString: className) == "IOBlockStorageDriver" {
                IOObjectRetain(current)
                return current
            }

            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                return nil
            }
            owned.append(parent)
            current = parent
        }
        return nil
    }

    private static func counters(_ driver: io_registry_entry_t) -> Counters? {
        guard let statistics = IORegistryEntryCreateCFProperty(
            driver,
            "Statistics" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any] else { return nil }

        func number(_ key: String) -> UInt64 {
            if let value = statistics[key] as? UInt64 { return value }
            if let value = statistics[key] as? Int { return UInt64(value) }
            if let value = statistics[key] as? NSNumber { return value.uint64Value }
            return 0
        }

        return Counters(
            bytes: number("Bytes (Read)") + number("Bytes (Written)"),
            ops: number("Operations (Read)") + number("Operations (Written)")
        )
    }
}
