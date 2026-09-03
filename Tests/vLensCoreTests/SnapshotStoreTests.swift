import Foundation
import Testing
@testable import vLensCore

private func makeStore() -> SnapshotStore {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vLensTests-\(UUID().uuidString)", isDirectory: true)
    return SnapshotStore(fileURL: dir.appendingPathComponent("inventory-snapshots.json"))
}

private func makeMetrics(vmCountTotal: Int = 10) -> InventorySnapshotMetrics {
    InventorySnapshotMetrics(
        vmCountTotal: vmCountTotal, vmCountPoweredOn: vmCountTotal, vmCountPoweredOff: 0, hostCount: 2,
        clusterCount: 1, datastoreCount: 3, datastoreMinFreePercent: 42.0, activeSnapshotCount: 0,
        toolsNotOKCount: 0, vHealthRedCount: 0, vHealthYellowCount: 0
    )
}

@Test func snapshotStoreLoadAllOnMissingFileReturnsEmpty() {
    let store = makeStore()
    #expect(store.loadAll().isEmpty)
}

@Test func addThenLoadRoundTrips() throws {
    let store = makeStore()
    let snapshot = InventorySnapshot(vCenterHost: "vcenter.local", label: "before migration", metrics: makeMetrics())

    try store.add(snapshot)

    let loaded = store.loadAll()
    #expect(loaded.count == 1)
    #expect(loaded[0].id == snapshot.id)
    #expect(loaded[0].metrics.vmCountTotal == 10)
}

@Test func addAccumulatesRatherThanReplacing() throws {
    let store = makeStore()
    try store.add(InventorySnapshot(vCenterHost: "vcenter.local", label: "first", metrics: makeMetrics(vmCountTotal: 10)))
    try store.add(InventorySnapshot(vCenterHost: "vcenter.local", label: "second", metrics: makeMetrics(vmCountTotal: 15)))

    #expect(store.loadAll().count == 2)
}

@Test func deleteRemovesOnlyTheMatchingSnapshot() throws {
    let store = makeStore()
    let keep = InventorySnapshot(vCenterHost: "vcenter.local", label: "keep", metrics: makeMetrics())
    let remove = InventorySnapshot(vCenterHost: "vcenter.local", label: "remove", metrics: makeMetrics())
    try store.add(keep)
    try store.add(remove)

    try store.delete(id: remove.id)

    let loaded = store.loadAll()
    #expect(loaded.count == 1)
    #expect(loaded[0].id == keep.id)
}
