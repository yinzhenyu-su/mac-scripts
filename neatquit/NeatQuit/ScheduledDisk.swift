import Foundation

/// 一块可弹出的物理磁盘。菜单按这个单位呈现目标。
struct ScheduledDisk: Equatable, Identifiable {
    /// 整盘 BSD 名，例如 `disk4`。
    let bsdName: String
    /// 触发时使用的主卷路径，例如 `/Volumes/Ventoy`。
    let mainVolumePath: String
    /// 菜单显示名，取主卷名。
    let displayName: String
    /// tooltip：厂商 · 型号 · 容量。
    let detail: String

    var id: String { bsdName }
}

/// 卷的纯值描述，便于在没有真实磁盘时测试命名规则。
struct DiskVolumeInfo: Equatable {
    let path: String
    let name: String
    let capacity: Int
    let isBrowsable: Bool
    let isReadOnly: Bool
}

enum DiskNaming {
    /// 主卷：可浏览、非只读、有名称的卷中容量最大的一个。
    static func mainVolume(in volumes: [DiskVolumeInfo]) -> DiskVolumeInfo? {
        volumes
            .filter { $0.isBrowsable && !$0.isReadOnly && !$0.name.isEmpty }
            .max { $0.capacity < $1.capacity }
    }

    /// 显示名回退链：主卷名 -> 整盘媒体名（去掉 ` Media`）-> 厂商 + 型号 -> 未命名磁盘。
    static func displayName(
        volumes: [DiskVolumeInfo],
        mediaName: String?,
        vendor: String?,
        model: String?
    ) -> String {
        if let main = mainVolume(in: volumes), !main.name.isEmpty {
            return main.name
        }
        if let mediaName, !mediaName.isEmpty {
            let trimmed = mediaName.hasSuffix(" Media")
                ? String(mediaName.dropLast(" Media".count))
                : mediaName
            if !trimmed.isEmpty { return trimmed }
        }
        let hardware = [vendor, model]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return hardware.isEmpty ? NSLocalizedString("disk.unnamed", comment: "") : hardware
    }

    static func detail(vendor: String?, model: String?, capacity: Int) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(capacity), countStyle: .file)
        return [vendor, model, size]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
