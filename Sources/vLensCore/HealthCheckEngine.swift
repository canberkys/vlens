import Foundation

/// Computes vHealth findings from data already collected for the other
/// tabs — matches RVTools' own model (vHealth doesn't do a separate
/// collection pass, it evaluates rules over vInfo/vSnapshot/vTools/etc.).
///
/// Implements 15 of RVTools' 24 documented rules (numbering matches
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
///   #17 NTP issues (no servers configured, or ntpd not running)
///   #20 Warning if ESXi Shell is enabled on host
///   #21 Warning if SSH is enabled on host
///   #22 Disk I/O performance tip (PVSCSI controller count vs. disk count/size)
///   #23 In-memory performance tip (NUMA exposure vs. hot-add/cores-per-socket)
///   host config status not green (rolled into the vHealth concept generally)
/// The remaining 9 rules (floppy connected, zombie VMDK/VM, certificate
/// expiry, inconsistent folder names, config-issue events, etc.) need
/// data this app doesn't collect
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
        disks: [VMDiskInfo] = [],
        memory: [VMMemoryInfo] = [],
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
            // #20/#21 — service keys confirmed against govmomi's own
            // simulator fixtures ("TSM" = ESXi Shell, "TSM-SSH" = SSH).
            if host.esxiShellEnabled {
                results.append(HealthCheckResult(
                    id: "host.shell.\(host.id)",
                    severity: .yellow,
                    rule: "ESXi Shell enabled",
                    message: "\(host.name): ESXi Shell (TSM) is enabled.",
                    relatedObject: host.name
                ))
            }
            if host.sshEnabled {
                results.append(HealthCheckResult(
                    id: "host.ssh.\(host.id)",
                    severity: .yellow,
                    rule: "SSH enabled",
                    message: "\(host.name): SSH is enabled.",
                    relatedObject: host.name
                ))
            }
            // #17 — either no NTP servers configured, or servers are
            // configured but the ntpd service isn't actually running (a
            // real, common misconfiguration — the config alone doesn't
            // mean time is actually being synced).
            if host.ntpServerCount == 0 || !host.ntpdRunning {
                let reason = host.ntpServerCount == 0 ? "no NTP servers configured" : "ntpd is not running"
                results.append(HealthCheckResult(
                    id: "host.ntp.\(host.id)",
                    severity: .yellow,
                    rule: "NTP issue",
                    message: "\(host.name): \(reason).",
                    relatedObject: host.name
                ))
            }

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

        // #22 Disk I/O performance tip — RVTools' own documented rule and
        // thresholds (not user-adjustable in RVTools either, so not added
        // to HealthCheckThresholds): a VM with more than 3 disks totaling
        // over 750 GiB should spread them across at least 2 Paravirtual
        // SCSI controllers for lower latency; fewer than 2 means every
        // disk funnels through the same queue.
        let disksByVM = Dictionary(grouping: disks, by: \.vmName)
        for vm in vms where vm.powerState == .poweredOn {
            guard let vmDisks = disksByVM[vm.name] else { continue }
            let totalDiskGiB = Double(vmDisks.reduce(0) { $0 + $1.capacityMiB }) / 1024.0
            guard vmDisks.count > 3, totalDiskGiB > 750, vm.pvscsiControllerCount < 2 else { continue }
            results.append(HealthCheckResult(
                id: "diskperf.\(vm.vmUUID)",
                severity: .yellow,
                rule: "Disk I/O performance tip",
                message: "\(vm.name): \(vmDisks.count) disks (\(String(format: "%.0f", totalDiskGiB)) GiB total) on only \(vm.pvscsiControllerCount) Paravirtual SCSI controller(s) — spreading disks across multiple PVSCSI controllers lowers latency.",
                relatedObject: vm.name
            ))
        }

        // #23 In-memory performance tip — RVTools' documented rule also
        // checks a `vnumaOnCpuHotaddExposed` VM setting; that isn't a
        // documented, reliably-sourceable vim25 API property (unlike every
        // other field this engine reads), so it's deliberately left out
        // rather than guessed at. The other three conditions (>=4 cores,
        // CPU/memory hot-add, one core per socket) are each real collected
        // fields and implemented as documented — any one of them can
        // prevent virtual NUMA from being exposed to the guest OS.
        let cpuByVM = Dictionary(cpus.map { ($0.vmName, $0) }, uniquingKeysWith: { first, _ in first })
        let memoryByVM = Dictionary(memory.map { ($0.vmName, $0) }, uniquingKeysWith: { first, _ in first })
        for vm in vms where vm.powerState == .poweredOn {
            guard let cpu = cpuByVM[vm.name], cpu.cpuCount >= 4 else { continue }
            let reason: String?
            if cpu.hotAddEnabled {
                reason = "CPU Hot Add is enabled"
            } else if memoryByVM[vm.name]?.hotAddEnabled == true {
                reason = "Memory Hot Add is enabled"
            } else if cpu.coresPerSocket == 1 {
                reason = "only 1 core per socket is configured"
            } else {
                reason = nil
            }
            guard let reason else { continue }
            results.append(HealthCheckResult(
                id: "memperf.\(vm.vmUUID)",
                severity: .yellow,
                rule: "In-memory performance tip",
                message: "\(vm.name): \(cpu.cpuCount) vCPUs but \(reason) — this can prevent virtual NUMA from being exposed to the guest, hurting memory-latency-sensitive workloads.",
                relatedObject: vm.name
            ))
        }

        return results
    }
}
