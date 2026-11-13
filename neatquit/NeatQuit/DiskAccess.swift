import Foundation
import OSLog

/// macOS 的「可移除宗卷」授权是懒加载的：第一次真正读取卷内容时才会弹窗。
/// 如果等到定时任务到点才第一次读取，无人值守的弹出会卡在系统授权对话框上，
/// 所以创建规则前先做一次无害的目录读取，把授权提前到用户还在场的时候。
enum DiskAccess {
    private static let logger = Logger(subsystem: "fun.bgm.neatquit", category: "DiskAccess")

    /// 读取卷根目录以触发并确认系统授权。
    /// 返回 false 表示用户拒绝、路径不可读或磁盘已不在。
    static func requestAccess(to path: String) -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: path)
            return true
        } catch {
            logger.info(
                "disk access unavailable: path=\(path, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }
}
