import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case vInfo, vCpu, vMemory, vDisk, vSnapshot, vTools, vNetwork, vCD, vUSB, vPartition, vPerformance, vApp
    case vHost, vDatastore, vCluster, vRP
    case vSwitch, vPort, dvSwitch, dvPort, vNic, vmk
    case vHBA, vMultipath
    case vLicense, vHealth
    case snapshots

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vInfo: return "vInfo"
        case .vCpu: return "vCPU"
        case .vMemory: return "vMemory"
        case .vDisk: return "vDisk"
        case .vSnapshot: return "vSnapshot"
        case .vTools: return "vTools"
        case .vNetwork: return "vNetwork"
        case .vCD: return "vCD"
        case .vUSB: return "vUSB"
        case .vPartition: return "vPartition"
        case .vPerformance: return "vPerformance"
        case .vApp: return "vApp"
        case .vHost: return "vHost"
        case .vDatastore: return "vDatastore"
        case .vCluster: return "vCluster"
        case .vRP: return "vRP"
        case .vSwitch: return "vSwitch"
        case .vPort: return "vPort"
        case .dvSwitch: return "dvSwitch"
        case .dvPort: return "dvPort"
        case .vNic: return "vNic"
        case .vmk: return "vSC+VMK"
        case .vHBA: return "vHBA"
        case .vMultipath: return "vMultipath"
        case .vLicense: return "vLicense"
        case .vHealth: return "vHealth"
        case .snapshots: return "Snapshots"
        }
    }

    /// Sidebar section. Kept here (not re-derived in ContentView) so tab
    /// metadata stays in one place as more tabs get added — a new case
    /// only needs a `label` and a `group`, nothing in the view layer.
    var group: AppTabGroup {
        switch self {
        case .vInfo, .vCpu, .vMemory, .vDisk, .vSnapshot, .vTools, .vNetwork, .vCD, .vUSB, .vPartition, .vPerformance, .vApp: return .vm
        case .vHost, .vDatastore, .vCluster, .vRP: return .infrastructure
        case .vSwitch, .vPort, .dvSwitch, .dvPort, .vNic, .vmk: return .networking
        case .vHBA, .vMultipath: return .storage
        case .vLicense: return .licensing
        case .vHealth: return .health
        case .snapshots: return .history
        }
    }
}

/// Order here is display order in the sidebar.
enum AppTabGroup: String, CaseIterable {
    case vm = "VM"
    case infrastructure = "Infrastructure"
    case networking = "Networking"
    case storage = "Storage"
    case licensing = "Licensing"
    case health = "Health"
    /// Local, persisted point-in-time records — not vCenter inventory data
    /// like every other group, hence its own group rather than folding into
    /// Health. See `InventorySnapshot`/`SnapshotStore`.
    case history = "History"

    var tabs: [AppTab] {
        AppTab.allCases.filter { $0.group == self }
    }
}
