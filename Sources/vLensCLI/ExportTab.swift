import Foundation
import vLensCore

/// The subset of tabs `vlens-cli export` can produce — the 24 "raw
/// collected inventory" tabs (mirrors `ContentView.exportCurrentTab`'s
/// switch, deliberately kept as a separate CLI-side copy rather than a
/// shared abstraction: `AppTab` carries UI-only concerns — labels, sidebar
/// grouping, SF Symbols — that have no CLI equivalent) plus vHealth, which
/// is cheap to recompute here since `HealthCheckEngine` is pure vLensCore.
/// Snapshots/vPerformance aren't included: Snapshots is `vlens-cli
/// snapshot`'s own job, vPerformance needs its own time-window collection
/// pass and is out of scope for v1 automation.
enum ExportTab: String, CaseIterable {
    case vinfo, vcpu, vmemory, vdisk, vsnapshot, vtools, vnetwork
    case vhost, vdatastore, vcluster, vlicense
    case vswitch, vport, dvswitch, dvport
    case vrp, vapp, vhba, vnic, vmk, vmultipath
    case vcd, vusb, vpartition
    case vhealth
}

enum ExportFormat: String {
    case csv, xlsx
}

/// Renders one tab as CSV/XLSX `Data`, ready to write straight to
/// `--output`. `CSVWriter`/`XLSXWriter` and every model's `CSVExportable`
/// conformance already live in `vLensCore` (`CSVExport.swift`) — this just
/// picks the right typed array per tab key, same as the GUI's export menu.
func exportData(
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
