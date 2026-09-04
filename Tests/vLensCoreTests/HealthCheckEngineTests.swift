import Foundation
import Testing
@testable import vLensCore

@Test func flagsLowDatastoreFreeSpace() {
    let datastore = DatastoreInfo(
        id: "ds1", name: "ds1", type: "VMFS", capacityMiB: 100_000, freeMiB: 5_000,
        numVMsTotal: 1, numHostsConnected: 1, url: nil
    )

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [datastore], hosts: [], cpus: []
    )

    #expect(results.count == 1)
    #expect(results[0].severity == .red)
    #expect(results[0].rule == "Datastore free space")
}

@Test func doesNotFlagHealthyDatastore() {
    let datastore = DatastoreInfo(
        id: "ds1", name: "ds1", type: "VMFS", capacityMiB: 100_000, freeMiB: 50_000,
        numVMsTotal: 1, numHostsConnected: 1, url: nil
    )

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [datastore], hosts: [], cpus: []
    )

    #expect(results.isEmpty)
}

@Test func flagsOutdatedVMwareTools() {
    let tools = VMToolsInfo(
        id: "vm1", vmName: "web-01", powerState: .poweredOn, hardwareVersion: "vmx-19",
        toolsStatus: .toolsOld, toolsVersion: "11.0.0", hostName: "esxi-01", clusterName: nil
    )

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [tools], datastores: [], hosts: [], cpus: []
    )

    #expect(results.count == 1)
    #expect(results[0].severity == .yellow)
}

@Test func flagsHighVCPUPerCoreRatio() {
    let host = HostInfo(
        id: "h1", name: "esxi-01", datacenterName: nil, clusterName: nil, configStatus: .green,
        cpuModel: "Xeon", cpuMhz: 2000, numCpuCores: 4, numCpuThreads: 8, cpuUsagePercent: nil,
        memoryTotalMiB: 65536, memoryUsagePercent: nil, numNics: 2, numHbas: 1, numVMsTotal: 2,
        numVMsRunning: 2, esxVersion: "8.0", vendor: nil, model: nil, maintenanceMode: false
    )
    let cpus = [
        VMCpuInfo(
            id: "vm1", vmName: "vm1", powerState: .poweredOn, cpuCount: 12, sockets: 1,
            coresPerSocket: 12, overallUsageMHz: nil, reservationMHz: 0, limitMHz: -1,
            hotAddEnabled: false, hotRemoveEnabled: false, hostName: "esxi-01", clusterName: nil
        ),
        VMCpuInfo(
            id: "vm2", vmName: "vm2", powerState: .poweredOn, cpuCount: 8, sockets: 1,
            coresPerSocket: 8, overallUsageMHz: nil, reservationMHz: 0, limitMHz: -1,
            hotAddEnabled: false, hotRemoveEnabled: false, hostName: "esxi-01", clusterName: nil
        )
    ]

    // 20 active vCPUs on a 4-core host => ratio 5.0, above the default 4.0 threshold
    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [host], cpus: cpus
    )

    #expect(results.contains { $0.rule == "vCPU per core ratio" })
}

@Test func flagsConnectedCDROM() {
    let cd = CDInfo(id: "cd1", vmName: "web-01", powerState: .poweredOn, connected: true, isoPath: "[ds1] installer.iso", deviceName: nil)

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [], cpus: [], cds: [cd]
    )

    #expect(results.count == 1)
    #expect(results[0].rule == "CDROM connected")
}

@Test func doesNotFlagDisconnectedCDROM() {
    let cd = CDInfo(id: "cd1", vmName: "web-01", powerState: .poweredOn, connected: false, isoPath: nil, deviceName: nil)

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [], cpus: [], cds: [cd]
    )

    #expect(results.isEmpty)
}

@Test func flagsLowGuestDiskFreeSpace() {
    let partition = PartitionInfo(id: "p1", vmName: "web-01", diskPath: "C:\\", capacityMiB: 100_000, freeMiB: 2_000)

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [], cpus: [], partitions: [partition]
    )

    #expect(results.count == 1)
    #expect(results[0].severity == .red)
    #expect(results[0].rule == "Guest disk free space")
}

@Test func flagsHighVMCountOnDatastore() {
    let datastore = DatastoreInfo(
        id: "ds1", name: "ds1", type: "VMFS", capacityMiB: 100_000, freeMiB: 50_000,
        numVMsTotal: 40, numHostsConnected: 1, url: nil
    )

    // 40 VMs registered, above the default threshold of 30
    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [datastore], hosts: [], cpus: []
    )

    #expect(results.count == 1)
    #expect(results[0].rule == "VMs per datastore")
}

/// `operationalState` is `ScsiLun.operationalState` (LUN-level: "ok",
/// "degraded", "error", etc.) — NOT per-path state ("active"/"standby"/
/// "dead"). These fixtures originally used the wrong vocabulary, which
/// meant they couldn't have caught the real bug this rule had (every real
/// "ok" LUN was being flagged red) — an external code review caught it,
/// verified against `helper/main.go`'s actual Go field mapping first.
@Test func flagsDegradedMultipath() {
    let multipath = MultipathInfo(
        id: "mp1", hostName: "esxi-01", disk: "naa.001", displayName: "SAN LUN 0", numPaths: 4,
        operationalState: ["degraded"], vendor: "NETAPP", model: "LUN"
    )

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [], cpus: [], multipaths: [multipath]
    )

    #expect(results.count == 1)
    #expect(results[0].severity == .red)
    #expect(results[0].rule == "Multipath state")
}

@Test func doesNotFlagHealthyMultipath() {
    let multipath = MultipathInfo(
        id: "mp1", hostName: "esxi-01", disk: "naa.001", displayName: "SAN LUN 0", numPaths: 4,
        operationalState: ["ok"], vendor: "NETAPP", model: "LUN"
    )

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [], cpus: [], multipaths: [multipath]
    )

    #expect(results.isEmpty)
}

@Test func flagsConsolidationNeeded() {
    let vm = VirtualMachineInfo(
        name: "web-01", powerState: .poweredOn, template: false, guestOSFullName: nil, cpuCount: 2,
        memoryMiB: 4096, hostName: "esxi-01", clusterName: nil, resourcePoolName: nil,
        primaryIPAddress: nil, vmwareToolsStatus: nil, vmUUID: "vm1", consolidationNeeded: true
    )

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [], cpus: [], vms: [vm]
    )

    #expect(results.count == 1)
    #expect(results[0].rule == "Consolidation needed")
}

@Test func doesNotFlagVMWithoutConsolidationNeeded() {
    let vm = VirtualMachineInfo(
        name: "web-01", powerState: .poweredOn, template: false, guestOSFullName: nil, cpuCount: 2,
        memoryMiB: 4096, hostName: "esxi-01", clusterName: nil, resourcePoolName: nil,
        primaryIPAddress: nil, vmwareToolsStatus: nil, vmUUID: "vm1"
    )

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [], cpus: [], vms: [vm]
    )

    #expect(results.isEmpty)
}
