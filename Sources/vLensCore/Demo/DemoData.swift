import Foundation

/// Mock data for exercising the UI without a live vCenter connection. Not
/// wired into any production/export path — purely a development and
/// screenshot aid, same role as vInventory's mockData.js. Every generator
/// below derives from the same `virtualMachines()` list so VM names/hosts/
/// clusters line up consistently across tabs, the way a real collection
/// would.
public enum DemoData {
    private static let clusters = ["prod-cluster-01", "prod-cluster-02", "dev-cluster-01"]
    private static let hostNames = ["esxi-01.lab.local", "esxi-02.lab.local", "esxi-03.lab.local", "esxi-04.lab.local"]
    private static let datacenters = ["DC-Istanbul", "DC-Frankfurt"]

    public static func virtualMachines(count: Int = 40) -> [VirtualMachineInfo] {
        let roles = ["APP", "WEB", "DB", "DC", "FILE", "PROXY", "CACHE", "MAIL", "BUILD", "DR"]
        let envs = ["PROD", "DEV", "TEST", "DMZ", "STG"]
        let guestOS = [
            "Microsoft Windows Server 2022 (64-bit)",
            "Microsoft Windows Server 2019 (64-bit)",
            "Red Hat Enterprise Linux 9 (64-bit)",
            "Ubuntu Linux (64-bit)",
            "SUSE Linux Enterprise 15 (64-bit)",
            "CentOS 7 (64-bit)"
        ]
        let pools = ["Resources", "prod-pool", "dev-pool", nil]
        let toolsStates = ["toolsOk", "toolsOld", "toolsNotRunning", "toolsNotInstalled"]

        return (1...count).map { i in
            let role = roles[i % roles.count]
            let env = envs[i % envs.count]
            let name = "\(role)-\(env)-\(String(format: "%02d", i))"
            let power: PowerState = i % 10 == 0 ? .poweredOff : (i % 17 == 0 ? .suspended : .poweredOn)
            let cpu = [1, 2, 4, 8, 16][i % 5]
            let memory = [2048, 4096, 8192, 16384, 32768][i % 5]

            // Most VMs live in a folder named after themselves (the healthy
            // case for RVTools #11) — every 15th one instead sits in a
            // leftover, mismatched folder, just enough to demonstrate the
            // "Inconsistent folder name" vHealth rule without flooding
            // demo mode with findings.
            let folder = (i % 15 == 0) ? "Legacy-Migration-Holding" : name

            return VirtualMachineInfo(
                name: name,
                powerState: power,
                template: i % 23 == 0,
                guestOSFullName: guestOS[i % guestOS.count],
                cpuCount: cpu,
                memoryMiB: memory,
                hostName: hostNames[i % hostNames.count],
                clusterName: clusters[i % clusters.count],
                resourcePoolName: pools[i % pools.count],
                primaryIPAddress: power == .poweredOn ? "10.0.\(i % 8).\(10 + i % 200)" : nil,
                vmwareToolsStatus: power == .poweredOn ? toolsStates[i % toolsStates.count] : nil,
                vmUUID: "demo-\(UUID().uuidString)",
                folderName: folder
            )
        }
    }

    public static func cpus(for vms: [VirtualMachineInfo]) -> [VMCpuInfo] {
        vms.enumerated().map { i, vm in
            let sockets = vm.cpuCount >= 4 ? vm.cpuCount / 2 : 1
            return VMCpuInfo(
                id: vm.vmUUID,
                vmName: vm.name,
                powerState: vm.powerState,
                cpuCount: vm.cpuCount,
                sockets: sockets,
                coresPerSocket: sockets > 0 ? vm.cpuCount / sockets : vm.cpuCount,
                overallUsageMHz: vm.powerState == .poweredOn ? (i * 137) % 4000 : nil,
                reservationMHz: 0,
                limitMHz: -1,
                hotAddEnabled: i % 4 == 0,
                hotRemoveEnabled: i % 5 == 0,
                hostName: vm.hostName,
                clusterName: vm.clusterName
            )
        }
    }

    public static func memory(for vms: [VirtualMachineInfo]) -> [VMMemoryInfo] {
        vms.enumerated().map { i, vm in
            let consumed = vm.powerState == .poweredOn ? Int(Double(vm.memoryMiB) * 0.6) : nil
            return VMMemoryInfo(
                id: vm.vmUUID,
                vmName: vm.name,
                powerState: vm.powerState,
                sizeMiB: vm.memoryMiB,
                overheadMiB: vm.powerState == .poweredOn ? 64 + i % 32 : nil,
                consumedMiB: consumed,
                activeMiB: consumed.map { Int(Double($0) * 0.5) },
                sharedMiB: consumed.map { $0 / 10 },
                swappedMiB: i % 13 == 0 ? 128 : 0,
                balloonedMiB: i % 19 == 0 ? 256 : 0,
                reservationMiB: 0,
                limitMiB: -1,
                hotAddEnabled: i % 4 == 0,
                hostName: vm.hostName,
                clusterName: vm.clusterName
            )
        }
    }

    public static func disks(for vms: [VirtualMachineInfo]) -> [VMDiskInfo] {
        vms.flatMap { vm -> [VMDiskInfo] in
            let diskCount = vm.template ? 1 : (vm.cpuCount >= 8 ? 2 : 1)
            return (0..<diskCount).map { d in
                VMDiskInfo(
                    id: "\(vm.vmUUID)-disk\(d)",
                    vmName: vm.name,
                    powerState: vm.powerState,
                    diskLabel: "Hard disk \(d + 1)",
                    capacityMiB: [40960, 81920, 163840, 512000][d % 4],
                    thinProvisioned: d == 0,
                    diskMode: "persistent",
                    controller: "SCSI controller 0",
                    unitNumber: d,
                    datastorePath: "[datastore-0\((d % 3) + 1)] \(vm.name)/\(vm.name).vmdk",
                    hostName: vm.hostName
                )
            }
        }
    }

    public static func snapshots(for vms: [VirtualMachineInfo]) -> [VMSnapshotInfo] {
        vms.enumerated().compactMap { i, vm in
            guard i % 7 == 0 else { return nil } // ~15% of VMs, matches vInventory's own demo-mode ratio
            let daysAgo = [1, 3, 9, 22, 60][i % 5]
            return VMSnapshotInfo(
                id: "\(vm.vmUUID)-snap",
                vmName: vm.name,
                powerState: vm.powerState,
                snapshotName: "Before patching \(daysAgo)d ago",
                snapshotDescription: i % 2 == 0 ? "Pre-maintenance snapshot" : nil,
                createdDate: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date(),
                sizeMiBTotal: 1024 + i * 37,
                quiesced: i % 3 == 0,
                hostName: vm.hostName,
                clusterName: vm.clusterName
            )
        }
    }

    public static func tools(for vms: [VirtualMachineInfo]) -> [VMToolsInfo] {
        vms.enumerated().map { i, vm in
            let status: ToolsStatus = vm.template
                ? .toolsNotInstalled
                : (ToolsStatus(rawValue: vm.vmwareToolsStatus ?? "toolsNotRunning") ?? .toolsNotRunning)
            return VMToolsInfo(
                id: vm.vmUUID,
                vmName: vm.name,
                powerState: vm.powerState,
                hardwareVersion: "vmx-\(19 + i % 2)",
                toolsStatus: status,
                toolsVersion: status == .toolsOk || status == .toolsOld ? "12.3.5" : nil,
                hostName: vm.hostName,
                clusterName: vm.clusterName
            )
        }
    }

    public static func networks(for vms: [VirtualMachineInfo]) -> [VMNetworkInfo] {
        let portGroups = ["PG-Prod-VLAN10", "PG-Dev-VLAN20", "PG-DMZ-VLAN30", "PG-Management"]
        let adapterTypes = ["VMXNET3", "VMXNET3", "VMXNET3", "E1000"]
        return vms.enumerated().map { i, vm in
            VMNetworkInfo(
                id: "\(vm.vmUUID)-net0", vmName: vm.name, powerState: vm.powerState,
                nicLabel: "Network adapter 1", adapterType: adapterTypes[i % adapterTypes.count],
                network: portGroups[i % portGroups.count], connected: vm.powerState == .poweredOn,
                macAddress: String(format: "00:50:56:%02x:%02x:%02x", (i / 256) % 256, i % 256, (i * 7) % 256),
                ipv4Address: vm.primaryIPAddress, ipv6Address: nil
            )
        }
    }

    public static func performanceMetrics(for vms: [VirtualMachineInfo], intervalMinutes: Int) -> [VMPerformanceInfo] {
        let now = Date()
        return vms.enumerated().compactMap { i, vm in
            guard vm.powerState == .poweredOn else { return nil }
            let avgCpu = Double(10 + (i * 7) % 60)
            let avgRam = Double(20 + (i * 11) % 55)
            return VMPerformanceInfo(
                id: "\(vm.vmUUID)-perf", vmName: vm.name, intervalMinutes: intervalMinutes, collectedAt: now,
                avgCpuUsagePercent: avgCpu, maxCpuUsagePercent: min(avgCpu + Double(5 + i % 30), 100),
                avgRamUsagePercent: avgRam, maxRamUsagePercent: min(avgRam + Double(5 + i % 20), 100),
                maxReadIOSizeBytes: Int64(4096 + (i % 8) * 4096), maxWriteIOSizeBytes: Int64(2048 + (i % 6) * 4096)
            )
        }
    }

    public static func hosts() -> [HostInfo] {
        hostNames.enumerated().map { i, hostName in
            HostInfo(
                id: hostName,
                name: hostName,
                datacenterName: datacenters[i % datacenters.count],
                clusterName: clusters[i % clusters.count],
                configStatus: i == 3 ? .yellow : .green,
                cpuModel: "Intel Xeon Gold 6338",
                cpuMhz: 2000,
                numCpuCores: 32,
                numCpuThreads: 64,
                cpuUsagePercent: Double(20 + i * 15),
                memoryTotalMiB: 524_288,
                memoryUsagePercent: Double(30 + i * 12),
                numNics: 4,
                numHbas: 2,
                numVMsTotal: 10 + i * 3,
                numVMsRunning: 8 + i * 2,
                // One host deliberately on an already-EOL version (real
                // endoflife.date data: ESXi 7.0's general support ended
                // 2025-10-02) — demonstrates the ESXi end-of-life badge
                // (GitHub issue #19) without fabricating a fake EOL date.
                esxVersion: i == 0 ? "7.0.3" : "8.0.3",
                // Representative build strings (mock data, like the rest
                // of this file) — real format, not tied to a specific
                // verified patch.
                esxBuild: i == 0 ? "19193900" : "24022515",
                vendor: "Dell Inc.",
                model: "PowerEdge R750",
                maintenanceMode: false
            )
        }
    }

    public static func datastores() -> [DatastoreInfo] {
        (1...6).map { i in
            let capacity = [2_097_152, 4_194_304, 8_388_608][i % 3]
            let free = i == 5 ? Int(Double(capacity) * 0.06) : Int(Double(capacity) * Double.random(in: 0.15...0.55))
            return DatastoreInfo(
                id: "datastore-0\(i)",
                name: "datastore-0\(i)",
                type: i % 4 == 0 ? "NFS" : "VMFS",
                capacityMiB: capacity,
                freeMiB: free,
                numVMsTotal: 6 + i,
                numHostsConnected: hostNames.count,
                url: "ds:///vmfs/volumes/datastore-0\(i)/"
            )
        }
    }

    public static func clusterInfos() -> [ClusterInfo] {
        clusters.enumerated().map { i, name in
            ClusterInfo(
                id: name,
                name: name,
                configStatus: .green,
                numHosts: 4,
                numEffectiveHosts: 4,
                totalCpuMHz: 256_000,
                totalMemoryMiB: 2_097_152,
                haEnabled: true,
                admissionControlEnabled: i != 2,
                drsEnabled: true,
                drsDefaultVMBehavior: "fullyAutomated"
            )
        }
    }

    public static func licenses() -> [LicenseInfo] {
        [
            LicenseInfo(
                name: "vSphere 8 Enterprise Plus",
                key: "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE",
                labels: ["Owner: IT-Infra"],
                costUnit: "cpuPackage",
                total: 32,
                used: 24,
                expirationDate: nil,
                features: ["vMotion", "DRS", "HA", "vSAN"]
            ),
            LicenseInfo(
                name: "vCenter Server Standard",
                key: "FFFFF-GGGGG-HHHHH-IIIII-JJJJJ",
                labels: [],
                costUnit: "instance",
                total: 1,
                used: 1,
                expirationDate: nil,
                features: ["Inventory Service"]
            ),
            LicenseInfo(
                name: "vSAN Enterprise (Evaluation)",
                key: "KKKKK-LLLLL-MMMMM-NNNNN-OOOOO",
                labels: ["Owner: Storage Team"],
                costUnit: "cpuPackage",
                total: 8,
                used: 8,
                expirationDate: ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: 12, to: Date()) ?? Date()),
                features: ["vSAN"]
            )
        ]
    }

    public static func vSwitches() -> [VSwitchInfo] {
        hostNames.map { host in
            VSwitchInfo(
                id: "\(host)-vSwitch0", hostName: host, name: "vSwitch0",
                numPorts: 1536, numPortsAvailable: 1500, mtu: 1500, numUplinks: 2, numPortGroups: 3
            )
        }
    }

    public static func vPorts() -> [VPortInfo] {
        let groups = [("VM Network", 0), ("Management Network", 0), ("vMotion", 20)]
        return hostNames.flatMap { host in
            groups.map { name, vlan in
                VPortInfo(id: "\(host)-\(name)", hostName: host, switchName: "vSwitch0", name: name, vlanId: vlan)
            }
        }
    }

    public static func dvSwitches() -> [DVSwitchInfo] {
        [
            DVSwitchInfo(id: "dvs-0", name: "DSwitch-Prod", uuid: "50 1a 2b 3c 4d 5e 6f 70-00 11 22 33 44 55 66 77",
                         numPorts: 512, numHosts: hostNames.count, numPortGroups: 4)
        ]
    }

    public static func dvPorts() -> [DVPortInfo] {
        [
            DVPortInfo(id: "dvpg-0", name: "DSwitch-Prod-DVUplinks", switchName: "DSwitch-Prod", numPorts: 8, vlanId: nil),
            DVPortInfo(id: "dvpg-1", name: "Production-VLAN100", switchName: "DSwitch-Prod", numPorts: 64, vlanId: 100),
            DVPortInfo(id: "dvpg-2", name: "DMZ-VLAN200", switchName: "DSwitch-Prod", numPorts: 32, vlanId: 200)
        ]
    }

    public static func resourcePools() -> [ResourcePoolInfo] {
        clusters.map { cluster in
            ResourcePoolInfo(
                id: "\(cluster)-Resources", name: "Resources", ownerName: cluster,
                cpuReservationMHz: 0, cpuLimitMHz: -1, memoryReservationMiB: 0, memoryLimitMiB: -1, numVMs: 10
            )
        }
    }

    public static func vApps() -> [VAppInfo] {
        [
            VAppInfo(id: "vapp-1", name: "3-Tier-WebApp", ownerName: clusters.first, numVMs: 3, productName: "Internal Web Platform", productVersion: "2.4.0")
        ]
    }

    public static func hbas() -> [HBAInfo] {
        hostNames.map { host in
            HBAInfo(id: "\(host)-vmhba0", hostName: host, device: "vmhba0", model: "Smart Array P440ar", driver: "nhpsa", status: "online")
        }
    }

    public static func nics() -> [NicInfo] {
        hostNames.flatMap { host in
            [
                NicInfo(id: "\(host)-vmnic0", hostName: host, device: "vmnic0", mac: "00:50:56:aa:bb:01", linkSpeedMb: 10000, driver: "ntg3"),
                NicInfo(id: "\(host)-vmnic1", hostName: host, device: "vmnic1", mac: "00:50:56:aa:bb:02", linkSpeedMb: 10000, driver: "ntg3")
            ]
        }
    }

    public static func vmKernels() -> [VMKernelInfo] {
        hostNames.map { host in
            VMKernelInfo(id: "\(host)-vmk0", hostName: host, device: "vmk0", portGroup: "Management Network", ipAddress: "10.0.1.\(hostNames.firstIndex(of: host)! + 10)", mac: "00:50:56:cc:dd:01")
        }
    }

    public static func multipaths() -> [MultipathInfo] {
        hostNames.map { host in
            MultipathInfo(
                id: "\(host)-naa.001", hostName: host, disk: "naa.6000c29a1b2c3d4e", displayName: "Local Disk (naa.6000c29a1b2c3d4e)",
                numPaths: 2, operationalState: ["ok"], vendor: "DELL", model: "MD3820f"
            )
        }
    }

    public static func cds(for vms: [VirtualMachineInfo]) -> [CDInfo] {
        vms.enumerated().compactMap { i, vm in
            guard i % 4 == 0 else { return nil }
            return CDInfo(id: "\(vm.vmUUID)-cd", vmName: vm.name, powerState: vm.powerState, connected: false, isoPath: nil, deviceName: "Client Device")
        }
    }

    public static func floppies(for vms: [VirtualMachineInfo]) -> [FloppyInfo] {
        vms.enumerated().compactMap { i, vm in
            // One connected floppy so the vHealth "Floppy connected" rule
            // (RVTools #2) is actually demonstrable in demo mode.
            guard i == 1 else { return nil }
            return FloppyInfo(id: "\(vm.vmUUID)-floppy", vmName: vm.name, powerState: vm.powerState, connected: true)
        }
    }

    public static func usbs(for vms: [VirtualMachineInfo]) -> [USBInfo] {
        vms.enumerated().compactMap { i, vm in
            guard i % 15 == 0 else { return nil }
            return USBInfo(id: "\(vm.vmUUID)-usb", vmName: vm.name, powerState: vm.powerState, connected: true, vendor: 0x0781, product: 0x5581)
        }
    }

    public static func partitions(for vms: [VirtualMachineInfo]) -> [PartitionInfo] {
        vms.enumerated().compactMap { i, vm in
            guard vm.powerState == .poweredOn, !vm.template else { return nil }
            let capacity = [40960, 81920, 163840][i % 3]
            let free = Int(Double(capacity) * Double.random(in: 0.08...0.6))
            return PartitionInfo(id: "\(vm.vmUUID)-c", vmName: vm.name, diskPath: "C:\\", capacityMiB: capacity, freeMiB: free)
        }
    }
}
