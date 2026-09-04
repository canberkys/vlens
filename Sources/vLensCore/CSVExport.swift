import Foundation

/// A row type that knows how to render itself as CSV — matches RVTools'
/// most-used export path (see rvtools.txt's CLI section: `-ExportToCSV`
/// per tab). One `.csv` per tab, same convention.
public protocol CSVExportable {
    static var csvHeader: [String] { get }
    /// One entry per `csvHeader` column, same order — declares whether
    /// `XLSXWriter` should write that column as a real numeric cell or as
    /// text, regardless of what the string value happens to look like. CSV
    /// export ignores this entirely (a `.csv` has no cell types); it exists
    /// purely so XLSX doesn't have to guess from the value itself, which
    /// silently mangled things like a VM named "00123" (loses the leading
    /// zero once it becomes the number 123) or a two-part version string
    /// like "8.0" (same problem) — see `XLSXColumnType`.
    static var xlsxColumnTypes: [XLSXColumnType] { get }
    var csvRow: [String] { get }
}

public enum CSVWriter {
    public static func write<T: CSVExportable>(_ rows: [T]) -> String {
        var lines = [render(T.csvHeader)]
        lines.append(contentsOf: rows.map { render($0.csvRow) })
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func render(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    /// Neutralizes CSV/formula injection: a field starting with `=`, `+`,
    /// `-`, `@`, tab, or CR is a formula to Excel/Numbers/Sheets when the
    /// file is opened — vCenter data (VM names, notes) is untrusted input
    /// that could otherwise execute in the opening spreadsheet app. Prefixing
    /// with a single quote is the standard mitigation (OWASP CSV injection);
    /// it displays literally and doesn't affect the field's real value.
    private static func neutralizeFormulaInjection(_ field: String) -> String {
        guard let first = field.unicodeScalars.first else { return field }
        let triggers: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]
        guard triggers.contains(first) else { return field }
        return "'" + field
    }

    /// RFC 4180: quote any field containing a comma, quote, or newline;
    /// double up embedded quotes.
    private static func escape(_ field: String) -> String {
        let field = neutralizeFormulaInjection(field)
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

extension VirtualMachineInfo: CSVExportable {
    public static var csvHeader: [String] {
        ["VM", "Powerstate", "Template", "Guest OS", "CPUs", "Memory MiB", "Host", "Cluster", "Resource Pool", "Primary IP", "VMware Tools", "VM UUID"]
    }
    public static var xlsxColumnTypes: [XLSXColumnType] {
        [.text, .text, .text, .text, .number, .number, .text, .text, .text, .text, .text, .text]
    }
    public var csvRow: [String] {
        [name, powerState.rawValue, template ? "True" : "False", guestOSFullName ?? "", "\(cpuCount)", "\(memoryMiB)", hostName, clusterName ?? "", resourcePoolName ?? "", primaryIPAddress ?? "", vmwareToolsStatus ?? "", vmUUID]
    }
}

extension VMCpuInfo: CSVExportable {
    public static var csvHeader: [String] {
        ["VM", "Powerstate", "CPUs", "Sockets", "Cores p/s", "Overall MHz", "Hot Add", "Hot Remove", "Host", "Cluster"]
    }
    public static var xlsxColumnTypes: [XLSXColumnType] {
        [.text, .text, .number, .number, .number, .number, .text, .text, .text, .text]
    }
    public var csvRow: [String] {
        [vmName, powerState.rawValue, "\(cpuCount)", "\(sockets)", "\(coresPerSocket)", overallUsageMHz.map(String.init) ?? "", hotAddEnabled ? "True" : "False", hotRemoveEnabled ? "True" : "False", hostName, clusterName ?? ""]
    }
}

extension VMMemoryInfo: CSVExportable {
    public static var csvHeader: [String] {
        ["VM", "Powerstate", "Size MiB", "Consumed MiB", "Active MiB", "Shared MiB", "Swapped MiB", "Ballooned MiB", "Host", "Cluster"]
    }
    public static var xlsxColumnTypes: [XLSXColumnType] {
        [.text, .text, .number, .number, .number, .number, .number, .number, .text, .text]
    }
    public var csvRow: [String] {
        [vmName, powerState.rawValue, "\(sizeMiB)", consumedMiB.map(String.init) ?? "", activeMiB.map(String.init) ?? "", sharedMiB.map(String.init) ?? "", swappedMiB.map(String.init) ?? "", balloonedMiB.map(String.init) ?? "", hostName, clusterName ?? ""]
    }
}

extension VMDiskInfo: CSVExportable {
    public static var csvHeader: [String] {
        ["VM", "Disk", "Capacity MiB", "Thin", "Disk Mode", "Controller", "Path", "Host"]
    }
    public static var xlsxColumnTypes: [XLSXColumnType] {
        [.text, .text, .number, .text, .text, .text, .text, .text]
    }
    public var csvRow: [String] {
        [vmName, diskLabel, "\(capacityMiB)", thinProvisioned ? "True" : "False", diskMode, controller, datastorePath, hostName]
    }
}

extension VMSnapshotInfo: CSVExportable {
    public static var csvHeader: [String] {
        ["VM", "Snapshot", "Description", "Created", "Age (days)", "Size MiB", "Quiesced", "Host", "Cluster"]
    }
    public static var xlsxColumnTypes: [XLSXColumnType] {
        [.text, .text, .text, .text, .number, .number, .text, .text, .text]
    }
    public var csvRow: [String] {
        [vmName, snapshotName, snapshotDescription ?? "", ISO8601DateFormatter().string(from: createdDate), "\(ageInDays)", sizeMiBTotal.map(String.init) ?? "", quiesced ? "True" : "False", hostName, clusterName ?? ""]
    }
}

extension VMToolsInfo: CSVExportable {
    public static var csvHeader: [String] {
        ["VM", "Powerstate", "HW Version", "Tools", "Tools Version", "Host", "Cluster"]
    }
    public static var xlsxColumnTypes: [XLSXColumnType] {
        [.text, .text, .text, .text, .text, .text, .text]
    }
    public var csvRow: [String] {
        [vmName, powerState.rawValue, hardwareVersion, toolsStatus.rawValue, toolsVersion ?? "", hostName, clusterName ?? ""]
    }
}

extension HostInfo: CSVExportable {
    public static var csvHeader: [String] {
        ["Host", "Cluster", "Status", "CPU Model", "Cores", "CPU %", "Memory MiB", "Mem %", "VMs Running", "VMs Total", "ESXi Version"]
    }
    public static var xlsxColumnTypes: [XLSXColumnType] {
        [.text, .text, .text, .text, .number, .number, .number, .number, .number, .number, .text]
    }
    public var csvRow: [String] {
        [name, clusterName ?? "", configStatus.rawValue, cpuModel, "\(numCpuCores)", cpuUsagePercent.map { String(format: "%.0f", $0) } ?? "", "\(memoryTotalMiB)", memoryUsagePercent.map { String(format: "%.0f", $0) } ?? "", "\(numVMsRunning)", "\(numVMsTotal)", esxVersion]
    }
}

extension DatastoreInfo: CSVExportable {
    public static var csvHeader: [String] {
        ["Datastore", "Type", "Capacity MiB", "Free MiB", "Free %", "VMs", "Hosts"]
    }
    public static var xlsxColumnTypes: [XLSXColumnType] {
        [.text, .text, .number, .number, .number, .number, .number]
    }
    public var csvRow: [String] {
        [name, type, "\(capacityMiB)", "\(freeMiB)", String(format: "%.1f", freePercent), "\(numVMsTotal)", "\(numHostsConnected)"]
    }
}

extension ClusterInfo: CSVExportable {
    public static var csvHeader: [String] {
        ["Cluster", "Status", "Hosts", "Effective Hosts", "Total CPU MHz", "Total Memory MiB", "HA", "DRS", "Admission Control"]
    }
    public static var xlsxColumnTypes: [XLSXColumnType] {
        [.text, .text, .number, .number, .number, .number, .text, .text, .text]
    }
    public var csvRow: [String] {
        [name, configStatus.rawValue, "\(numHosts)", "\(numEffectiveHosts)", "\(totalCpuMHz)", "\(totalMemoryMiB)", haEnabled ? "Enabled" : "Disabled", drsEnabled ? "Enabled" : "Disabled", admissionControlEnabled ? "Enabled" : "Disabled"]
    }
}

extension HealthCheckResult: CSVExportable {
    public static var csvHeader: [String] { ["Severity", "Rule", "Object", "Message"] }
    public static var xlsxColumnTypes: [XLSXColumnType] { [.text, .text, .text, .text] }
    public var csvRow: [String] { [severity.rawValue, rule, relatedObject, message] }
}

extension LicenseInfo: CSVExportable {
    public static var csvHeader: [String] {
        ["Name", "Key", "Labels", "Cost Unit", "Total", "Used", "Expiration Date", "Features"]
    }
    public static var xlsxColumnTypes: [XLSXColumnType] {
        [.text, .text, .text, .text, .number, .number, .text, .text]
    }
    public var csvRow: [String] {
        [name, key, labels.joined(separator: "; "), costUnit, "\(total)", "\(used)", expirationDate ?? "", features.joined(separator: "; ")]
    }
}

extension VSwitchInfo: CSVExportable {
    public static var csvHeader: [String] {
        ["Switch", "Host", "Ports", "Ports Available", "MTU", "Uplinks", "Port Groups"]
    }
    public static var xlsxColumnTypes: [XLSXColumnType] {
        [.text, .text, .number, .number, .number, .number, .number]
    }
    public var csvRow: [String] {
        [name, hostName, "\(numPorts)", "\(numPortsAvailable)", "\(mtu)", "\(numUplinks)", "\(numPortGroups)"]
    }
}

extension VPortInfo: CSVExportable {
    public static var csvHeader: [String] { ["Port Group", "Switch", "Host", "VLAN"] }
    public static var xlsxColumnTypes: [XLSXColumnType] { [.text, .text, .text, .number] }
    public var csvRow: [String] { [name, switchName, hostName, "\(vlanId)"] }
}

extension DVSwitchInfo: CSVExportable {
    public static var csvHeader: [String] { ["Switch", "UUID", "Ports", "Hosts", "Port Groups"] }
    public static var xlsxColumnTypes: [XLSXColumnType] { [.text, .text, .number, .number, .number] }
    public var csvRow: [String] { [name, uuid, "\(numPorts)", "\(numHosts)", "\(numPortGroups)"] }
}

extension DVPortInfo: CSVExportable {
    public static var csvHeader: [String] { ["Port Group", "Switch", "Ports", "VLAN"] }
    public static var xlsxColumnTypes: [XLSXColumnType] { [.text, .text, .number, .number] }
    public var csvRow: [String] { [name, switchName, "\(numPorts)", vlanId.map(String.init) ?? ""] }
}

extension ResourcePoolInfo: CSVExportable {
    public static var csvHeader: [String] {
        ["Resource Pool", "Owner", "CPU Reservation MHz", "CPU Limit MHz", "Memory Reservation MiB", "Memory Limit MiB", "VMs"]
    }
    public static var xlsxColumnTypes: [XLSXColumnType] {
        [.text, .text, .number, .number, .number, .number, .number]
    }
    public var csvRow: [String] {
        [name, ownerName ?? "", "\(cpuReservationMHz)", "\(cpuLimitMHz)", "\(memoryReservationMiB)", "\(memoryLimitMiB)", "\(numVMs)"]
    }
}

extension VAppInfo: CSVExportable {
    public static var csvHeader: [String] { ["vApp", "Owner", "VMs", "Product", "Version"] }
    public static var xlsxColumnTypes: [XLSXColumnType] { [.text, .text, .number, .text, .text] }
    public var csvRow: [String] { [name, ownerName ?? "", "\(numVMs)", productName ?? "", productVersion ?? ""] }
}

extension HBAInfo: CSVExportable {
    public static var csvHeader: [String] { ["Host", "Device", "Model", "Driver", "Status"] }
    public static var xlsxColumnTypes: [XLSXColumnType] { [.text, .text, .text, .text, .text] }
    public var csvRow: [String] { [hostName, device, model, driver, status] }
}

extension NicInfo: CSVExportable {
    public static var csvHeader: [String] { ["Host", "Device", "MAC", "Link Speed Mb", "Driver"] }
    public static var xlsxColumnTypes: [XLSXColumnType] { [.text, .text, .text, .number, .text] }
    public var csvRow: [String] { [hostName, device, mac, linkSpeedMb.map(String.init) ?? "", driver ?? ""] }
}

extension VMKernelInfo: CSVExportable {
    public static var csvHeader: [String] { ["Host", "Device", "Port Group", "IP Address", "MAC"] }
    public static var xlsxColumnTypes: [XLSXColumnType] { [.text, .text, .text, .text, .text] }
    public var csvRow: [String] { [hostName, device, portGroup, ipAddress ?? "", mac] }
}

extension MultipathInfo: CSVExportable {
    public static var csvHeader: [String] { ["Host", "Disk", "Display Name", "Paths", "Operational State", "Vendor", "Model"] }
    public static var xlsxColumnTypes: [XLSXColumnType] { [.text, .text, .text, .number, .text, .text, .text] }
    public var csvRow: [String] { [hostName, disk, displayName, "\(numPaths)", operationalState.joined(separator: "; "), vendor, model] }
}

extension CDInfo: CSVExportable {
    public static var csvHeader: [String] { ["VM", "Powerstate", "Connected", "ISO Path", "Device Name"] }
    public static var xlsxColumnTypes: [XLSXColumnType] { [.text, .text, .text, .text, .text] }
    public var csvRow: [String] { [vmName, powerState.rawValue, connected ? "True" : "False", isoPath ?? "", deviceName ?? ""] }
}

extension USBInfo: CSVExportable {
    public static var csvHeader: [String] { ["VM", "Powerstate", "Connected", "Vendor", "Product"] }
    public static var xlsxColumnTypes: [XLSXColumnType] { [.text, .text, .text, .text, .text] }
    public var csvRow: [String] { [vmName, powerState.rawValue, connected ? "True" : "False", vendor.map(String.init) ?? "", product.map(String.init) ?? ""] }
}

extension VMNetworkInfo: CSVExportable {
    public static var csvHeader: [String] {
        ["VM", "Powerstate", "NIC Label", "Adapter Type", "Network", "Connected", "MAC Address", "IPv4 Address", "IPv6 Address"]
    }
    public static var xlsxColumnTypes: [XLSXColumnType] {
        [.text, .text, .text, .text, .text, .text, .text, .text, .text]
    }
    public var csvRow: [String] {
        [vmName, powerState.rawValue, nicLabel, adapterType, network, connected ? "True" : "False", macAddress, ipv4Address ?? "", ipv6Address ?? ""]
    }
}

extension InventorySnapshot: CSVExportable {
    public static var csvHeader: [String] {
        ["Label", "Taken At", "vCenter Host"] + SnapshotMetricDescriptor.all.map(\.label)
    }
    public static var xlsxColumnTypes: [XLSXColumnType] {
        [.text, .text, .text] + Array(repeating: .number, count: SnapshotMetricDescriptor.all.count)
    }
    public var csvRow: [String] {
        [displayLabel, ISO8601DateFormatter().string(from: takenAt), vCenterHost]
            + SnapshotMetricDescriptor.all.map { $0.value(metrics).map { String(format: "%.2f", $0) } ?? "" }
    }
}

extension VMPerformanceInfo: CSVExportable {
    public static var csvHeader: [String] {
        ["VM", "Interval (min)", "Avg CPU %", "Max CPU %", "Avg RAM %", "Max RAM %", "Max Read IO Size", "Max Write IO Size", "Collected At"]
    }
    public static var xlsxColumnTypes: [XLSXColumnType] {
        [.text, .number, .number, .number, .number, .number, .number, .number, .text]
    }
    public var csvRow: [String] {
        [
            vmName, "\(intervalMinutes)",
            avgCpuUsagePercent.map { String(format: "%.1f", $0) } ?? "",
            maxCpuUsagePercent.map { String(format: "%.1f", $0) } ?? "",
            avgRamUsagePercent.map { String(format: "%.1f", $0) } ?? "",
            maxRamUsagePercent.map { String(format: "%.1f", $0) } ?? "",
            maxReadIOSizeBytes.map(String.init) ?? "",
            maxWriteIOSizeBytes.map(String.init) ?? "",
            ISO8601DateFormatter().string(from: collectedAt)
        ]
    }
}

extension PartitionInfo: CSVExportable {
    public static var csvHeader: [String] { ["VM", "Disk Path", "Capacity MiB", "Free MiB", "Free %"] }
    public static var xlsxColumnTypes: [XLSXColumnType] { [.text, .text, .number, .number, .number] }
    public var csvRow: [String] { [vmName, diskPath, "\(capacityMiB)", "\(freeMiB)", String(format: "%.1f", freePercent)] }
}
