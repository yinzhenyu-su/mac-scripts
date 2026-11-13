import DiskArbitration
import Foundation

/// 枚举可弹出的物理磁盘。枚举只在打开菜单与打开面板时进行，不做常驻监听。
enum DiskCatalog {
    private static let keys: [URLResourceKey] = [
        .volumeIsEjectableKey,
        .volumeIsLocalKey,
        .volumeIsBrowsableKey,
        .volumeIsReadOnlyKey,
        .volumeTotalCapacityKey,
        .volumeLocalizedNameKey,
        .volumeIsRootFileSystemKey,
    ]

    static func ejectableDisks() -> [ScheduledDisk] {
        guard let session = DASessionCreate(nil) else { return [] }
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        struct Group {
            var bsdName: String
            var volumes: [DiskVolumeInfo]
            var mediaName: String?
            var vendor: String?
            var model: String?
            var capacity: Int
        }

        var groups: [String: Group] = [:]
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsEjectable == true,
                  values.volumeIsLocal == true,
                  values.volumeIsRootFileSystem != true
            else { continue }

            let path = url.path
            // 排除 App 自身所在盘与家目录所在盘。
            if Bundle.main.bundleURL.path.hasPrefix(path) { continue }
            if NSHomeDirectory().hasPrefix(path) { continue }

            guard let volumeDisk = DADiskCreateFromVolumePath(nil, session, url as CFURL),
                  let whole = DADiskCopyWholeDisk(volumeDisk)
            else { continue }
            let description = DADiskCopyDescription(whole) as? [String: Any] ?? [:]
            guard let bsdName = description[kDADiskDescriptionMediaBSDNameKey as String] as? String else {
                continue
            }

            let info = DiskVolumeInfo(
                path: path,
                name: values.volumeLocalizedName ?? "",
                capacity: values.volumeTotalCapacity ?? 0,
                isBrowsable: values.volumeIsBrowsable ?? false,
                isReadOnly: values.volumeIsReadOnly ?? false
            )
            let mediaSize = (description[kDADiskDescriptionMediaSizeKey as String] as? NSNumber)?.intValue
            if var group = groups[bsdName] {
                group.volumes.append(info)
                group.capacity = max(group.capacity, mediaSize ?? info.capacity)
                groups[bsdName] = group
            } else {
                groups[bsdName] = Group(
                    bsdName: bsdName,
                    volumes: [info],
                    mediaName: description[kDADiskDescriptionMediaNameKey as String] as? String,
                    vendor: description[kDADiskDescriptionDeviceVendorKey as String] as? String,
                    model: description[kDADiskDescriptionDeviceModelKey as String] as? String,
                    capacity: mediaSize ?? info.capacity
                )
            }
        }

        return groups.values.compactMap { group -> ScheduledDisk? in
            guard let main = DiskNaming.mainVolume(in: group.volumes) else { return nil }
            return ScheduledDisk(
                bsdName: group.bsdName,
                mainVolumePath: main.path,
                displayName: DiskNaming.displayName(
                    volumes: group.volumes,
                    mediaName: group.mediaName,
                    vendor: group.vendor,
                    model: group.model
                ),
                detail: DiskNaming.detail(
                    vendor: group.vendor,
                    model: group.model,
                    capacity: group.capacity
                )
            )
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    static func isVolumeMounted(path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
