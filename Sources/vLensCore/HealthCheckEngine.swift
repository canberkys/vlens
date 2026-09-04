import Foundation

/// Computes vHealth findings from data already collected for the other
/// tabs — matches RVTools' own model (vHealth doesn't do a separate
/// collection pass, it evaluates rules over vInfo/vSnapshot/vTools/etc.).
///
/// Implements 10 of RVTools' 24 documented rules (numbering matches
/// rvtools.txt's vHealth section):
///   #1  VM has a CDROM device connected!
///   #3  VM has an active snapshot!
///   #4  VMware tools are out of date, not running or not installed!
///   #5  On disk xx is yy% disk space available! (guest-level, threshold zz%)
///   #6  On datastore xx is yy% disk space available! (threshold zz%)
///   #7  There are xx virtual CPUs active per core on this host! (threshold zz)
///   #8  There are xx VMs active on this datastore! (threshold zz)
///   #12 Multipath operational state (degraded/dead paths)
///   #13 Virtual machine consolidation needed
///   host config status not green (rolled into the vHealth concept generally)
/// The remaining 14 rules (floppy connected, zombie VMDK/VM, NTP/cert
/// expiry, config-issue events, etc.) need data this app doesn't collect
/// yet — add them incrementally as their source tabs are built.
public enum HealthCheckEngine {
    public static func evaluate(
        snapshots: [VMSnapshotInfo],
        tools: [VMToolsInfo],
        datastores: [DatastoreInfo],
        hosts: [HostInfo],
        cpus: [VMCpuInfo],
        cds: [CDInfo] = [],
        partitions: [PartitionInfo] = [],
        multipaths: [MultipathInfo] = [],
        vms: [VirtualMachineInfo] = [],
        thresholds: HealthCheckThresholds = HealthCheckThresholds()
    ) -> [HealthCheckResult] {
        var results: [HealthCheckResult] = []

        for vm in vms where vm.consolidationNeeded {
            results.append(HealthCheckResult(
                id: "consolidation.\(vm.vmUUID)",
                severity: .yellow,
                rule: "Consolidation needed",
                message: "\(vm.name): virtual machine disk consolidation needed.",
                relatedObject: vm.name
            ))
        }

        for snapshot in snapshots {
            results.append(HealthCheckResult(
                id: "snapshot.\(snapshot.id)",
                severity: .yellow,
                rule: "Active snapshot",
                message: "\(snapshot.vmName): active snapshot for \(snapshot.ageInDays) day(s) (\(snapshot.snapshotName)).",
                relatedObject: snapshot.vmName
            ))
        }

        for tool in tools where tool.toolsStatus != .toolsOk {
            results.append(HealthCheckResult(
                id: "tools.\(tool.id)",
                severity: tool.toolsStatus == .toolsNotInstalled ? .red : .yellow,
                rule: "VMware Tools",
                message: "\(tool.vmName): VMware Tools status is \(tool.toolsStatus.rawValue).",
                relatedObject: tool.vmName
            ))
        }

        for datastore in datastores {
            if datastore.freePercent < thresholds.datastoreFreeSpacePercent {
                results.append(HealthCheckResult(
                    id: "datastore.\(datastore.id)",
                    severity: .red,
                    rule: "Datastore free space",
                    message: "\(datastore.name): \(String(format: "%.1f", datastore.freePercent))% free space (threshold: \(Int(thresholds.datastoreFreeSpacePercent))%).",
                    relatedObject: datastore.name
                ))
            }

            // "Active" here means registered on the datastore (numVMsTotal),
            // not powered-on — vLens doesn't currently join VM-to-datastore
            // membership against power state, and RVTools' own rule #8
            // doesn't distinguish either.
            if datastore.numVMsTotal > thresholds.maxVMsPerDatastore {
                results.append(HealthCheckResult(
                    id: "datastore.vmcount.\(datastore.id)",
                    severity: .yellow,
                    rule: "VMs per datastore",
                    message: "\(datastore.name): \(datastore.numVMsTotal) VMs on this datastore (threshold: \(thresholds.maxVMsPerDatastore)).",
                    relatedObject: datastore.name
                ))
            }
        }

        for cd in cds where cd.connected {
            results.append(HealthCheckResult(
                id: "cd.\(cd.id)",
                severity: .yellow,
                rule: "CDROM connected",
                message: "\(cd.vmName): CD/DVD device is connected.",
                relatedObject: cd.vmName
            ))
        }

        for partition in partitions where partition.freePercent < thresholds.guestDiskFreeSpacePercent {
            results.append(HealthCheckResult(
                id: "partition.\(partition.id)",
                severity: .red,
                rule: "Guest disk free space",
                message: "\(partition.vmName): \(partition.diskPath) has \(String(format: "%.1f", partition.freePercent))% free space (threshold: \(Int(thresholds.guestDiskFreeSpacePercent))%).",
                relatedObject: partition.vmName
            ))
        }

        // `MultipathInfo.operationalState` is `ScsiLun.operationalState` —
        // the LUN's own operational state ("ok", "degraded", "error",
        // "lostCommunication", "off", "quiesced", "unbound" are the
        // documented vim25 values), NOT the per-path state of an individual
        // path within `HostMultipathInfo.Lun[].Path` (which uses a
        // different vocabulary — "active"/"standby"/"disabled"/"dead").
        // This rule originally checked for the wrong vocabulary — a
        // perfectly healthy LUN reporting "ok" would never match
        // "active"/"standby" and was flagged red on every real (and demo)
        // environment. `VMultipathTabView`'s own coloring already used the
        // correct "ok" baseline; this rule just hadn't matched it. Caught
        // by an external code review, verified against the real Go field
        // mapping (`helper/main.go`'s `collectMultipaths`) before fixing.
        for multipath in multipaths {
            let badStates = multipath.operationalState.filter { $0 != "ok" }
            if !badStates.isEmpty {
                results.append(HealthCheckResult(
                    id: "multipath.\(multipath.id)",
                    severity: .red,
                    rule: "Multipath state",
                    message: "\(multipath.hostName): \(multipath.displayName) is in state \(badStates.joined(separator: ", ")).",
                    relatedObject: multipath.hostName
                ))
            }
        }

        for host in hosts {
            let activeVCPUs = cpus
                .filter { $0.hostName == host.name && $0.powerState == .poweredOn }
                .reduce(0) { $0 + $1.cpuCount }
            guard host.numCpuCores > 0 else { continue }
            let ratio = Double(activeVCPUs) / Double(host.numCpuCores)
            if ratio > thresholds.vCPUsPerCoreWarning {
                results.append(HealthCheckResult(
                    id: "host.vcpu.\(host.id)",
                    severity: .yellow,
                    rule: "vCPU per core ratio",
                    message: "\(host.name): \(String(format: "%.1f", ratio)) active vCPUs per core (threshold: \(Int(thresholds.vCPUsPerCoreWarning))).",
                    relatedObject: host.name
                ))
            }

            if host.configStatus != .green {
                results.append(HealthCheckResult(
                    id: "host.config.\(host.id)",
                    severity: host.configStatus,
                    rule: "Host config status",
                    message: "\(host.name): config status \(host.configStatus.rawValue).",
                    relatedObject: host.name
                ))
            }
        }

        return results
    }
}
