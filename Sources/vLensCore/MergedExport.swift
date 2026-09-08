import Foundation

/// Multi-vCenter merge — vLens' equivalent of RVTools' separate
/// `RVToolsMergeExcelFiles.exe` tool. Deliberately the same shape: several
/// *separate* vCenters' collections (not simultaneous live connections,
/// which would require rearchitecting `ConnectionViewModel`'s single-
/// connection model) stitched into one export after the fact, tagging each
/// row with which vCenter it came from. Works with every existing model
/// for free — they're all already `CSVExportable`, so no per-model changes
/// were needed.
public struct MergedRow<T: CSVExportable>: CSVExportable {
    public let vCenterSource: String
    public let row: T

    public init(vCenterSource: String, row: T) {
        self.vCenterSource = vCenterSource
        self.row = row
    }

    public static var csvHeader: [String] { ["vCenter"] + T.csvHeader }
    public static var xlsxColumnTypes: [XLSXColumnType] { [.text] + T.xlsxColumnTypes }
    public var csvRow: [String] { [vCenterSource] + row.csvRow }
}

/// One vCenter's contribution to a merge — a name to tag its rows with,
/// plus its own collection and (separately, since `HealthCheckEngine` is
/// evaluated per-connection, not part of `CollectedInventory` itself) its
/// own vHealth findings.
public struct MergeSource: Sendable {
    public let name: String
    public let inventory: CollectedInventory
    public let healthChecks: [HealthCheckResult]

    public init(name: String, inventory: CollectedInventory, healthChecks: [HealthCheckResult]) {
        self.name = name
        self.inventory = inventory
        self.healthChecks = healthChecks
    }
}

/// Renders one tab across every given source as a single CSV/XLSX,
/// mirroring `exportData`'s per-tab switch exactly (same `ExportTab` cases,
/// same `CollectedInventory` fields) but tagging and concatenating rows
/// from all sources instead of reading from just one.
public func mergedExportData(tab: ExportTab, format: ExportFormat, sources: [MergeSource]) throws -> Data {
    func make<T: CSVExportable>(_ pick: (MergeSource) -> [T], sheet: String) throws -> Data {
        let merged: [MergedRow<T>] = sources.flatMap { source in
            pick(source).map { MergedRow(vCenterSource: source.name, row: $0) }
        }
        switch format {
        case .csv: return Data(CSVWriter.write(merged).utf8)
        case .xlsx: return try XLSXWriter.data(for: merged, sheetName: sheet)
        }
    }

    switch tab {
    case .vinfo: return try make({ $0.inventory.vms }, sheet: "vInfo")
    case .vcpu: return try make({ $0.inventory.cpus }, sheet: "vCPU")
    case .vmemory: return try make({ $0.inventory.memory }, sheet: "vMemory")
    case .vdisk: return try make({ $0.inventory.disks }, sheet: "vDisk")
    case .vsnapshot: return try make({ $0.inventory.snapshots }, sheet: "vSnapshot")
    case .vtools: return try make({ $0.inventory.tools }, sheet: "vTools")
    case .vnetwork: return try make({ $0.inventory.networks }, sheet: "vNetwork")
    case .vhost: return try make({ $0.inventory.hosts }, sheet: "vHost")
    case .vdatastore: return try make({ $0.inventory.datastores }, sheet: "vDatastore")
    case .vcluster: return try make({ $0.inventory.clusters }, sheet: "vCluster")
    case .vlicense: return try make({ $0.inventory.licenses }, sheet: "vLicense")
    case .vswitch: return try make({ $0.inventory.vSwitches }, sheet: "vSwitch")
    case .vport: return try make({ $0.inventory.ports }, sheet: "vPort")
    case .dvswitch: return try make({ $0.inventory.dvSwitches }, sheet: "dvSwitch")
    case .dvport: return try make({ $0.inventory.dvPorts }, sheet: "dvPort")
    case .vrp: return try make({ $0.inventory.resourcePools }, sheet: "vRP")
    case .vapp: return try make({ $0.inventory.vApps }, sheet: "vApp")
    case .vhba: return try make({ $0.inventory.hbas }, sheet: "vHBA")
    case .vnic: return try make({ $0.inventory.nics }, sheet: "vNic")
    case .vmk: return try make({ $0.inventory.vmKernels }, sheet: "vSC+VMK")
    case .vmultipath: return try make({ $0.inventory.multipaths }, sheet: "vMultipath")
    case .vcd: return try make({ $0.inventory.cds }, sheet: "vCD")
    case .vfloppy: return try make({ $0.inventory.floppies }, sheet: "vFloppy")
    case .vusb: return try make({ $0.inventory.usbs }, sheet: "vUSB")
    case .vpartition: return try make({ $0.inventory.partitions }, sheet: "vPartition")
    case .vhealth: return try make({ $0.healthChecks }, sheet: "vHealth")
    case .vsource: return try make({ [$0.inventory.vCenter].compactMap { $0 } }, sheet: "vSource")
    }
}
