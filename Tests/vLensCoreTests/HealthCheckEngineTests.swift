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
        numVMsRunning: 2, esxVersion: "8.0", esxBuild: "24022515", vendor: nil, model: nil, maintenanceMode: false
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

@Test func flagsConnectedFloppy() {
    let floppy = FloppyInfo(id: "floppy1", vmName: "web-01", powerState: .poweredOn, connected: true)

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [], cpus: [], floppies: [floppy]
    )

    #expect(results.count == 1)
    #expect(results[0].rule == "Floppy connected")
}

@Test func doesNotFlagDisconnectedFloppy() {
    let floppy = FloppyInfo(id: "floppy1", vmName: "web-01", powerState: .poweredOn, connected: false)

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [], cpus: [], floppies: [floppy]
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

// #22 Disk I/O performance tip — RVTools: running VM, >3 disks, >750 GiB
// total, <2 Paravirtual SCSI controllers.

private func makeDisk(vmName: String, capacityMiB: Int, index: Int) -> VMDiskInfo {
    VMDiskInfo(
        id: "\(vmName)-disk\(index)", vmName: vmName, powerState: .poweredOn,
        diskLabel: "Hard disk \(index)", capacityMiB: capacityMiB, thinProvisioned: false,
        diskMode: "persistent", controller: "SCSI controller (Paravirtual)", unitNumber: index,
        datastorePath: "[ds1] \(vmName)/disk\(index).vmdk", hostName: "esxi-01"
    )
}

@Test func flagsDiskIOPerformanceTip() {
    let vm = VirtualMachineInfo(
        name: "db-01", powerState: .poweredOn, template: false, guestOSFullName: nil, cpuCount: 4,
        memoryMiB: 16384, hostName: "esxi-01", clusterName: nil, resourcePoolName: nil,
        primaryIPAddress: nil, vmwareToolsStatus: nil, vmUUID: "vm1", pvscsiControllerCount: 1
    )
    // 4 disks x 250 GiB (256000 MiB) = 1000 GiB total, both thresholds cleared.
    let disks = (1...4).map { makeDisk(vmName: "db-01", capacityMiB: 256_000, index: $0) }

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [], cpus: [], vms: [vm], disks: disks
    )

    #expect(results.count == 1)
    #expect(results[0].rule == "Disk I/O performance tip")
}

@Test func doesNotFlagDiskIOPerformanceTipWithEnoughControllers() {
    let vm = VirtualMachineInfo(
        name: "db-01", powerState: .poweredOn, template: false, guestOSFullName: nil, cpuCount: 4,
        memoryMiB: 16384, hostName: "esxi-01", clusterName: nil, resourcePoolName: nil,
        primaryIPAddress: nil, vmwareToolsStatus: nil, vmUUID: "vm1", pvscsiControllerCount: 2
    )
    let disks = (1...4).map { makeDisk(vmName: "db-01", capacityMiB: 256_000, index: $0) }

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [], cpus: [], vms: [vm], disks: disks
    )

    #expect(results.isEmpty)
}

@Test func doesNotFlagDiskIOPerformanceTipWithFewDisks() {
    let vm = VirtualMachineInfo(
        name: "db-01", powerState: .poweredOn, template: false, guestOSFullName: nil, cpuCount: 4,
        memoryMiB: 16384, hostName: "esxi-01", clusterName: nil, resourcePoolName: nil,
        primaryIPAddress: nil, vmwareToolsStatus: nil, vmUUID: "vm1", pvscsiControllerCount: 1
    )
    // Only 3 disks (not > 3), even though large and under-controllered.
    let disks = (1...3).map { makeDisk(vmName: "db-01", capacityMiB: 256_000, index: $0) }

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [], cpus: [], vms: [vm], disks: disks
    )

    #expect(results.isEmpty)
}

// #23 In-memory performance tip — RVTools: running VM, >=4 cores, and
// (CPU hot add OR memory hot add OR one core per socket). The
// `vnumaOnCpuHotaddExposed` sub-condition RVTools also checks isn't a
// reliably-sourceable vim25 field, so it's deliberately not part of this
// implementation (see HealthCheckEngine.swift's doc comment).

@Test func flagsInMemoryPerformanceTipForHotAddCPU() {
    let vm = VirtualMachineInfo(
        name: "sql-01", powerState: .poweredOn, template: false, guestOSFullName: nil, cpuCount: 8,
        memoryMiB: 32768, hostName: "esxi-01", clusterName: nil, resourcePoolName: nil,
        primaryIPAddress: nil, vmwareToolsStatus: nil, vmUUID: "vm1"
    )
    let cpu = VMCpuInfo(
        id: "vm1", vmName: "sql-01", powerState: .poweredOn, cpuCount: 8, sockets: 2, coresPerSocket: 4,
        overallUsageMHz: nil, reservationMHz: 0, limitMHz: -1, hotAddEnabled: true, hotRemoveEnabled: false,
        hostName: "esxi-01", clusterName: nil
    )

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [], cpus: [cpu], vms: [vm]
    )

    #expect(results.count == 1)
    #expect(results[0].rule == "In-memory performance tip")
}

@Test func flagsInMemoryPerformanceTipForOneCorePerSocket() {
    let vm = VirtualMachineInfo(
        name: "sql-01", powerState: .poweredOn, template: false, guestOSFullName: nil, cpuCount: 4,
        memoryMiB: 32768, hostName: "esxi-01", clusterName: nil, resourcePoolName: nil,
        primaryIPAddress: nil, vmwareToolsStatus: nil, vmUUID: "vm1"
    )
    let cpu = VMCpuInfo(
        id: "vm1", vmName: "sql-01", powerState: .poweredOn, cpuCount: 4, sockets: 4, coresPerSocket: 1,
        overallUsageMHz: nil, reservationMHz: 0, limitMHz: -1, hotAddEnabled: false, hotRemoveEnabled: false,
        hostName: "esxi-01", clusterName: nil
    )

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [], cpus: [cpu], vms: [vm]
    )

    #expect(results.count == 1)
    #expect(results[0].rule == "In-memory performance tip")
}

@Test func doesNotFlagInMemoryPerformanceTipForHealthyConfig() {
    let vm = VirtualMachineInfo(
        name: "sql-01", powerState: .poweredOn, template: false, guestOSFullName: nil, cpuCount: 8,
        memoryMiB: 32768, hostName: "esxi-01", clusterName: nil, resourcePoolName: nil,
        primaryIPAddress: nil, vmwareToolsStatus: nil, vmUUID: "vm1"
    )
    let cpu = VMCpuInfo(
        id: "vm1", vmName: "sql-01", powerState: .poweredOn, cpuCount: 8, sockets: 2, coresPerSocket: 4,
        overallUsageMHz: nil, reservationMHz: 0, limitMHz: -1, hotAddEnabled: false, hotRemoveEnabled: false,
        hostName: "esxi-01", clusterName: nil
    )
    let memory = VMMemoryInfo(
        id: "vm1", vmName: "sql-01", powerState: .poweredOn, sizeMiB: 32768, overheadMiB: nil,
        consumedMiB: nil, activeMiB: nil, sharedMiB: nil, swappedMiB: nil, balloonedMiB: nil,
        reservationMiB: 0, limitMiB: -1, hotAddEnabled: false, hostName: "esxi-01", clusterName: nil
    )

    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [], cpus: [cpu], vms: [vm], memory: [memory]
    )

    #expect(results.isEmpty)
}

// #20/#21/#17 — ESXi Shell, SSH, NTP. Defaults on HostInfo's initializer
// (esxiShellEnabled/sshEnabled false, ntpdRunning true, ntpServerCount 1)
// are deliberately the "healthy" state, so a host built without
// overriding them never spuriously triggers these rules.

private func makeHost(
    esxiShellEnabled: Bool = false, sshEnabled: Bool = false,
    ntpdRunning: Bool = true, ntpServerCount: Int = 1
) -> HostInfo {
    HostInfo(
        id: "h1", name: "esxi-01", datacenterName: nil, clusterName: nil, configStatus: .green,
        cpuModel: "Xeon", cpuMhz: 2000, numCpuCores: 4, numCpuThreads: 8, cpuUsagePercent: nil,
        memoryTotalMiB: 65536, memoryUsagePercent: nil, numNics: 2, numHbas: 1, numVMsTotal: 0,
        numVMsRunning: 0, esxVersion: "8.0", esxBuild: "24022515", vendor: nil, model: nil,
        maintenanceMode: false, esxiShellEnabled: esxiShellEnabled, sshEnabled: sshEnabled,
        ntpdRunning: ntpdRunning, ntpServerCount: ntpServerCount
    )
}

@Test func flagsESXiShellEnabled() {
    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [makeHost(esxiShellEnabled: true)], cpus: []
    )
    #expect(results.contains { $0.rule == "ESXi Shell enabled" })
}

@Test func flagsSSHEnabled() {
    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [makeHost(sshEnabled: true)], cpus: []
    )
    #expect(results.contains { $0.rule == "SSH enabled" })
}

@Test func flagsNoNTPServersConfigured() {
    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [makeHost(ntpServerCount: 0)], cpus: []
    )
    #expect(results.contains { $0.rule == "NTP issue" })
}

@Test func flagsNtpdNotRunningDespiteConfiguredServers() {
    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [makeHost(ntpdRunning: false, ntpServerCount: 2)], cpus: []
    )
    #expect(results.contains { $0.rule == "NTP issue" })
}

@Test func doesNotFlagHealthyHostServices() {
    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [makeHost()], cpus: []
    )
    #expect(!results.contains { $0.rule == "ESXi Shell enabled" || $0.rule == "SSH enabled" || $0.rule == "NTP issue" })
}

// #24 Certificate expiry — RVTools: warn within a configurable number of
// days (default 90), red if already expired.

private func makeHostWithCert(daysUntilExpiry: Int?) -> HostInfo {
    let certNotAfter = daysUntilExpiry.map { Calendar.current.date(byAdding: .day, value: $0, to: Date())! }
    return HostInfo(
        id: "h1", name: "esxi-01", datacenterName: nil, clusterName: nil, configStatus: .green,
        cpuModel: "Xeon", cpuMhz: 2000, numCpuCores: 4, numCpuThreads: 8, cpuUsagePercent: nil,
        memoryTotalMiB: 65536, memoryUsagePercent: nil, numNics: 2, numHbas: 1, numVMsTotal: 0,
        numVMsRunning: 0, esxVersion: "8.0", esxBuild: "24022515", vendor: nil, model: nil,
        maintenanceMode: false, certNotAfter: certNotAfter
    )
}

@Test func flagsExpiredCertificateAsRed() {
    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [makeHostWithCert(daysUntilExpiry: -5)], cpus: []
    )
    let finding = try? #require(results.first { $0.rule == "Certificate expiry" })
    #expect(finding?.severity == .red)
}

@Test func flagsCertificateExpiringSoonAsYellow() {
    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [makeHostWithCert(daysUntilExpiry: 30)], cpus: [],
        thresholds: HealthCheckThresholds(certificateExpiryWarningDays: 90)
    )
    let finding = try? #require(results.first { $0.rule == "Certificate expiry" })
    #expect(finding?.severity == .yellow)
}

@Test func doesNotFlagCertificateFarFromExpiry() {
    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [makeHostWithCert(daysUntilExpiry: 365)], cpus: [],
        thresholds: HealthCheckThresholds(certificateExpiryWarningDays: 90)
    )
    #expect(!results.contains { $0.rule == "Certificate expiry" })
}

@Test func doesNotFlagWhenCertificateCouldNotBeRead() {
    let results = HealthCheckEngine.evaluate(
        snapshots: [], tools: [], datastores: [], hosts: [makeHostWithCert(daysUntilExpiry: nil)], cpus: []
    )
    #expect(!results.contains { $0.rule == "Certificate expiry" })
}
