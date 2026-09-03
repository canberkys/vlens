import Foundation

/// RVTools vApp tab — a container grouping related VMs with shared power-on
/// order/product metadata (rvtools.txt documents it as niche — RVTools'
/// own users rarely rely on it, which is why vLens deferred it this long).
/// `VirtualApp` (vim25) extends `ResourcePool`, so this mirrors
/// `ResourcePoolInfo`/`collectResourcePools` almost exactly — see
/// `collectVApps` in `helper/main.go`.
public struct VAppInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let ownerName: String?
    public let numVMs: Int
    public let productName: String?
    public let productVersion: String?

    public init(id: String, name: String, ownerName: String?, numVMs: Int, productName: String?, productVersion: String?) {
        self.id = id
        self.name = name
        self.ownerName = ownerName
        self.numVMs = numVMs
        self.productName = productName
        self.productVersion = productVersion
    }
}
