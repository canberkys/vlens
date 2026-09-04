import Foundation

/// The subset of tabs a headless caller (`vlens-cli export`, and Faz 10B's
/// Automation schedule) can produce — the 24 "raw collected inventory"
/// tabs (mirrors `ContentView.exportCurrentTab`'s switch, deliberately kept
/// as a separate copy rather than reusing `AppTab`: `AppTab` carries
/// UI-only concerns — labels, sidebar grouping, SF Symbols — that have no
/// headless equivalent) plus vHealth, which is cheap to recompute here
/// since `HealthCheckEngine` is pure vLensCore. Snapshots/vPerformance
/// aren't included: Snapshots is `vlens-cli snapshot`'s own job,
/// vPerformance needs its own time-window collection pass and is out of
/// scope for v1 automation.
///
/// Lives in `vLensCore` (not `vLensCLI`, where it started) specifically so
/// both `vlens-cli` and the GUI's Preferences "Automation" picker (Faz 10B)
/// reference the exact same tab list — a raw `String` duplicated in two
/// targets is exactly the kind of drift risk already fixed once this
/// session for `ConnectionProfile.keychainReferenceID`.
public enum ExportTab: String, CaseIterable, Codable, Sendable {
    case vinfo, vcpu, vmemory, vdisk, vsnapshot, vtools, vnetwork
    case vhost, vdatastore, vcluster, vlicense
    case vswitch, vport, dvswitch, dvport
    case vrp, vapp, vhba, vnic, vmk, vmultipath
    case vcd, vusb, vpartition
    case vhealth

    /// User-facing label for the Preferences Automation picker — matches
    /// the tab names shown elsewhere in the app (sidebar, Help).
    public var label: String {
        switch self {
        case .vinfo: return "vInfo"
        case .vcpu: return "vCPU"
        case .vmemory: return "vMemory"
        case .vdisk: return "vDisk"
        case .vsnapshot: return "vSnapshot"
        case .vtools: return "vTools"
        case .vnetwork: return "vNetwork"
        case .vhost: return "vHost"
        case .vdatastore: return "vDatastore"
        case .vcluster: return "vCluster"
        case .vlicense: return "vLicense"
        case .vswitch: return "vSwitch"
        case .vport: return "vPort"
        case .dvswitch: return "dvSwitch"
        case .dvport: return "dvPort"
        case .vrp: return "vRP"
        case .vapp: return "vApp"
        case .vhba: return "vHBA"
        case .vnic: return "vNic"
        case .vmk: return "vSC+VMK"
        case .vmultipath: return "vMultipath"
        case .vcd: return "vCD"
        case .vusb: return "vUSB"
        case .vpartition: return "vPartition"
        case .vhealth: return "vHealth"
        }
    }
}

public enum ExportFormat: String, Codable, Sendable, CaseIterable {
    case csv, xlsx
}

/// Renders one tab as CSV/XLSX `Data`, ready to write straight to a file.
/// `CSVWriter`/`XLSXWriter` and every model's `CSVExportable` conformance
/// already live in `vLensCore` (`CSVExport.swift`) — this just picks the
/// right typed array per tab key, same as the GUI's export menu.
public func exportData(
    tab: ExportTab, format: ExportFormat, inventory: CollectedInventory, healthChecks: [HealthCheckResult]
) throws -> Data {
    func make<T: CSVExportable>(_ rows: [T], sheet: String) throws -> Data {
        switch format {
        case .csv: return Data(CSVWriter.write(rows).utf8)
        case .xlsx: return try XLSXWriter.data(for: rows, sheetName: sheet)
        }
    }

    switch tab {
    case .vinfo: return try make(inventory.vms, sheet: "vInfo")
    case .vcpu: return try make(inventory.cpus, sheet: "vCPU")
    case .vmemory: return try make(inventory.memory, sheet: "vMemory")
    case .vdisk: return try make(inventory.disks, sheet: "vDisk")
    case .vsnapshot: return try make(inventory.snapshots, sheet: "vSnapshot")
    case .vtools: return try make(inventory.tools, sheet: "vTools")
    case .vnetwork: return try make(inventory.networks, sheet: "vNetwork")
    case .vhost: return try make(inventory.hosts, sheet: "vHost")
    case .vdatastore: return try make(inventory.datastores, sheet: "vDatastore")
    case .vcluster: return try make(inventory.clusters, sheet: "vCluster")
    case .vlicense: return try make(inventory.licenses, sheet: "vLicense")
    case .vswitch: return try make(inventory.vSwitches, sheet: "vSwitch")
    case .vport: return try make(inventory.ports, sheet: "vPort")
    case .dvswitch: return try make(inventory.dvSwitches, sheet: "dvSwitch")
    case .dvport: return try make(inventory.dvPorts, sheet: "dvPort")
    case .vrp: return try make(inventory.resourcePools, sheet: "vRP")
    case .vapp: return try make(inventory.vApps, sheet: "vApp")
    case .vhba: return try make(inventory.hbas, sheet: "vHBA")
    case .vnic: return try make(inventory.nics, sheet: "vNic")
    case .vmk: return try make(inventory.vmKernels, sheet: "vSC+VMK")
    case .vmultipath: return try make(inventory.multipaths, sheet: "vMultipath")
    case .vcd: return try make(inventory.cds, sheet: "vCD")
    case .vusb: return try make(inventory.usbs, sheet: "vUSB")
    case .vpartition: return try make(inventory.partitions, sheet: "vPartition")
    case .vhealth: return try make(healthChecks, sheet: "vHealth")
    }
}
