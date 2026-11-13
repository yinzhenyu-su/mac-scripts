import Foundation
import OSLog

/// 用系统自带的 `diskutil eject` 弹出磁盘：它会处理 APFS 合成容器、多卷盘与磁盘映像的整条链路。
/// 绝不使用 `-force`。
enum DiskEjector {
    private static let logger = Logger(subsystem: "fun.bgm.neatquit", category: "DiskEjector")

    /// 异步执行，completion 在主线程回调，参数表示是否成功弹出。
    static func eject(mainVolumePath: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = ["eject", mainVolumePath]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
            } catch {
                logger.info("eject failed to launch: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { completion(false) }
                return
            }

            process.waitUntilExit()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let status = process.terminationStatus
            logger.info(
                "eject finished: path=\(mainVolumePath, privacy: .public) status=\(status, privacy: .public) output=\(message, privacy: .public)"
            )
            DispatchQueue.main.async { completion(status == 0) }
        }
    }
}
