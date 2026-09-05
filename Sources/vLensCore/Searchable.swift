import Foundation

/// Backs the free-text filter box above every tab table. Each row exposes
/// the fields worth matching against as one lowercased blob — cheap enough
/// for MVP row counts (hundreds–low thousands); revisit with an index only
/// if profiling on a real large environment shows it's a bottleneck.
public protocol Searchable {
    var searchableText: String { get }
}

public extension Searchable {
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return searchableText.localizedCaseInsensitiveContains(query)
    }
}

extension VirtualMachineInfo: Searchable {
    public var searchableText: String {
        [name, guestOSFullName, hostName, clusterName, primaryIPAddress]
            .compactMap { $0 }.joined(separator: " ")
    }
}

extension VMCpuInfo: Searchable {
    public var searchableText: String { [vmName, hostName, clusterName].compactMap { $0 }.joined(separator: " ") }
}

extension VMMemoryInfo: Searchable {
    public var searchableText: String { [vmName, hostName, clusterName].compactMap { $0 }.joined(separator: " ") }
}

extension VMDiskInfo: Searchable {
    public var searchableText: String { [vmName, diskLabel, hostName, datastorePath].joined(separator: " ") }
}

extension VMSnapshotInfo: Searchable {
    public var searchableText: String {
        [vmName, snapshotName, snapshotDescription, hostName, clusterName].compactMap { $0 }.joined(separator: " ")
    }
}

extension VMToolsInfo: Searchable {
    public var searchableText: String { [vmName, hostName, clusterName].compactMap { $0 }.joined(separator: " ") }
}

extension HostInfo: Searchable {
    public var searchableText: String {
        [name, datacenterName, clusterName, cpuModel, vendor, model].compactMap { $0 }.joined(separator: " ")
    }
}

extension DatastoreInfo: Searchable {
    public var searchableText: String { [name, type].joined(separator: " ") }
}

extension ClusterInfo: Searchable {
    public var searchableText: String { name }
}

extension LicenseInfo: Searchable {
    public var searchableText: String {
        ([name, key] + labels + features).joined(separator: " ")
    }
}

extension VSwitchInfo: Searchable {
    public var searchableText: String { [hostName, name].joined(separator: " ") }
}

extension VPortInfo: Searchable {
    public var searchableText: String { [hostName, switchName, name].joined(separator: " ") }
}

extension DVSwitchInfo: Searchable {
    public var searchableText: String { [name, uuid].joined(separator: " ") }
}

extension DVPortInfo: Searchable {
    public var searchableText: String { [name, switchName].joined(separator: " ") }
}

extension ResourcePoolInfo: Searchable {
    public var searchableText: String { [name, ownerName].compactMap { $0 }.joined(separator: " ") }
}

extension VAppInfo: Searchable {
    public var searchableText: String { [name, ownerName, productName].compactMap { $0 }.joined(separator: " ") }
}

extension HBAInfo: Searchable {
    public var searchableText: String { [hostName, device, model, driver].joined(separator: " ") }
}

extension NicInfo: Searchable {
    public var searchableText: String { [hostName, device, mac].joined(separator: " ") }
}

extension VMKernelInfo: Searchable {
    public var searchableText: String { [hostName, device, portGroup, ipAddress].compactMap { $0 }.joined(separator: " ") }
}

extension MultipathInfo: Searchable {
    public var searchableText: String { [hostName, disk, displayName, vendor, model].joined(separator: " ") }
}

extension CDInfo: Searchable {
    public var searchableText: String { [vmName, isoPath, deviceName].compactMap { $0 }.joined(separator: " ") }
}

extension FloppyInfo: Searchable {
    public var searchableText: String { vmName }
}

extension USBInfo: Searchable {
    public var searchableText: String { vmName }
}

extension PartitionInfo: Searchable {
    public var searchableText: String { [vmName, diskPath].joined(separator: " ") }
}

extension InventorySnapshot: Searchable {
    public var searchableText: String { [label, vCenterHost].compactMap { $0 }.joined(separator: " ") }
}

extension VMPerformanceInfo: Searchable {
    public var searchableText: String { vmName }
}

extension VMNetworkInfo: Searchable {
    public var searchableText: String {
        [vmName, network, macAddress, ipv4Address, ipv6Address].compactMap { $0 }.joined(separator: " ")
    }
}

extension HealthCheckResult: Searchable {
    public var searchableText: String { [rule, relatedObject, message].joined(separator: " ") }
}
