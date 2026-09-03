import Foundation
import Testing
@testable import vLensCore

@Test func computeCountsFromAlreadyCollectedArrays() {
    let vms = [
        VirtualMachineInfo(name: "vm1", powerState: .poweredOn, template: false, guestOSFullName: nil, cpuCount: 1, memoryMiB: 1024, hostName: "h1", clusterName: nil, resourcePoolName: nil, primaryIPAddress: nil, vmwareToolsStatus: nil, vmUUID: "u1"),
        VirtualMachineInfo(name: "vm2", powerState: .poweredOff, template: false, guestOSFullName: nil, cpuCount: 1, memoryMiB: 1024, hostName: "h1", clusterName: nil, resourcePoolName: nil, primaryIPAddress: nil, vmwareToolsStatus: nil, vmUUID: "u2")
    ]
    let datastores = [
        DatastoreInfo(id: "ds1", name: "ds1", type: "VMFS", capacityMiB: 100_000, freeMiB: 5_000, numVMsTotal: 1, numHostsConnected: 1, url: nil),
        DatastoreInfo(id: "ds2", name: "ds2", type: "VMFS", capacityMiB: 100_000, freeMiB: 50_000, numVMsTotal: 1, numHostsConnected: 1, url: nil)
    ]
    let tools = [
        VMToolsInfo(id: "vm1", vmName: "vm1", powerState: .poweredOn, hardwareVersion: "vmx-19", toolsStatus: .toolsOk, toolsVersion: "12.0", hostName: "h1", clusterName: nil),
        VMToolsInfo(id: "vm2", vmName: "vm2", powerState: .poweredOff, hardwareVersion: "vmx-19", toolsStatus: .toolsNotRunning, toolsVersion: nil, hostName: "h1", clusterName: nil)
    ]
    let healthChecks = [
        HealthCheckResult(id: "a", severity: .red, rule: "x", message: "m", relatedObject: "vm1"),
        HealthCheckResult(id: "b", severity: .yellow, rule: "y", message: "m", relatedObject: "vm1")
    ]

    let metrics = InventorySnapshotMetrics.compute(
        vms: vms, hosts: [], clusters: [], datastores: datastores, snapshots: [], tools: tools, healthChecks: healthChecks
    )

    #expect(metrics.vmCountTotal == 2)
    #expect(metrics.vmCountPoweredOn == 1)
    #expect(metrics.vmCountPoweredOff == 1)
    #expect(metrics.datastoreMinFreePercent == 5.0) // ds1: 5000/100000 = 5%, the worse of the two
    #expect(metrics.toolsNotOKCount == 1)
    #expect(metrics.vHealthRedCount == 1)
    #expect(metrics.vHealthYellowCount == 1)
}

@Test func computeHandlesNoDatastoresWithoutCrashing() {
    let metrics = InventorySnapshotMetrics.compute(vms: [], hosts: [], clusters: [], datastores: [], snapshots: [], tools: [], healthChecks: [])
    #expect(metrics.datastoreMinFreePercent == nil)
}
