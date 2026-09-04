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

@Test func bulkDeleteRemovesOnlyTheMatchingSnapshots() throws {
    let store = makeStore()
    let keep = InventorySnapshot(vCenterHost: "vcenter.local", label: "keep", metrics: makeMetrics())
    let removeA = InventorySnapshot(vCenterHost: "vcenter.local", label: "removeA", metrics: makeMetrics())
    let removeB = InventorySnapshot(vCenterHost: "vcenter.local", label: "removeB", metrics: makeMetrics())
    try store.add(keep)
    try store.add(removeA)
    try store.add(removeB)

    try store.delete(ids: [removeA.id, removeB.id])

    let loaded = store.loadAll()
    #expect(loaded.count == 1)
    #expect(loaded[0].id == keep.id)
}

private func makeVM(name: String, uuid: String) -> VirtualMachineInfo {
    VirtualMachineInfo(
        name: name, powerState: .poweredOn, template: false, guestOSFullName: nil,
        cpuCount: 2, memoryMiB: 4096, hostName: "esx01.local", clusterName: "Cluster0",
        resourcePoolName: nil, primaryIPAddress: nil, vmwareToolsStatus: "toolsOk", vmUUID: uuid
    )
}

// Faz 9B — "Include full VM inventory" opt-in. `fullVMList` is nil by
// default (all pre-existing snapshots decode fine) and, when present, must
// round-trip through the same JSON persistence path as everything else so
// the Compare panel's "VM Changes" section (SnapshotsTabView.vmChanges) has
// real data to diff against.
@Test func fullVMListIsNilByDefault() throws {
    let store = makeStore()
    let snapshot = InventorySnapshot(vCenterHost: "vcenter.local", label: "basic", metrics: makeMetrics())
    try store.add(snapshot)

    #expect(store.loadAll()[0].fullVMList == nil)
}

@Test func fullVMListRoundTripsThroughPersistence() throws {
    let store = makeStore()
    let vms = [makeVM(name: "web-01", uuid: "uuid-1"), makeVM(name: "db-01", uuid: "uuid-2")]
    let snapshot = InventorySnapshot(vCenterHost: "vcenter.local", label: "full", metrics: makeMetrics(), fullVMList: vms)
    try store.add(snapshot)

    let loaded = try #require(store.loadAll().first?.fullVMList)
    #expect(loaded.count == 2)
    #expect(Set(loaded.map(\.vmUUID)) == Set(["uuid-1", "uuid-2"]))
}

// Faz 9B — the actual "added/removed" diff `SnapshotsTabView.vmChanges`
// performs: a simple set difference by `vmUUID` between two snapshots'
// `fullVMList`. Exercised here at the model level since the view function
// itself is private to the app target.
@Test func vmMembershipDiffDetectsAddedAndRemovedVMs() throws {
    let baseline = [makeVM(name: "web-01", uuid: "uuid-1"), makeVM(name: "db-01", uuid: "uuid-2")]
    let current = [makeVM(name: "web-01", uuid: "uuid-1"), makeVM(name: "app-02", uuid: "uuid-3")]

    let baselineIDs = Set(baseline.map(\.vmUUID))
    let currentIDs = Set(current.map(\.vmUUID))
    let added = current.filter { !baselineIDs.contains($0.vmUUID) }.map(\.name)
    let removed = baseline.filter { !currentIDs.contains($0.vmUUID) }.map(\.name)

    #expect(added == ["app-02"])
    #expect(removed == ["db-01"])
}

// Faz 9A — storage location override. `SnapshotStore.url(inDirectory:)` is
// what `ConnectionViewModel.snapshotStore` and
// `ConnectionViewModel.changeSnapshotStorageDirectory` both build on.
@Test func urlInDirectoryResolvesToDefaultWhenNil() {
    #expect(SnapshotStore.url(inDirectory: nil) == SnapshotStore.defaultURL)
}

@Test func urlInDirectoryUsesGivenDirectoryWhenProvided() {
    let customDir = FileManager.default.temporaryDirectory.appendingPathComponent("vLensTests-custom-\(UUID().uuidString)")
    #expect(SnapshotStore.url(inDirectory: customDir) == customDir.appendingPathComponent(SnapshotStore.fileName))
}

// Mirrors `ConnectionViewModel.changeSnapshotStorageDirectory`'s real
// behavior: copy (never move) the old file into the new location only if
// the new location doesn't already have one.
@Test func changingStorageDirectoryCopiesExistingFileWithoutRemovingOld() throws {
    let oldDir = FileManager.default.temporaryDirectory.appendingPathComponent("vLensTests-old-\(UUID().uuidString)")
    let newDir = FileManager.default.temporaryDirectory.appendingPathComponent("vLensTests-new-\(UUID().uuidString)")
    let oldStore = SnapshotStore(fileURL: SnapshotStore.url(inDirectory: oldDir))
    try oldStore.add(InventorySnapshot(vCenterHost: "vcenter.local", label: "before-move", metrics: makeMetrics()))

    let oldURL = SnapshotStore.url(inDirectory: oldDir)
    let newURL = SnapshotStore.url(inDirectory: newDir)
    try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: oldURL, to: newURL)

    #expect(FileManager.default.fileExists(atPath: oldURL.path))
    let newStore = SnapshotStore(fileURL: newURL)
    #expect(newStore.loadAll().count == 1)
    #expect(newStore.loadAll()[0].label == "before-move")
}

// Concurrent writers to the same file (the real scenario: the GUI and a
// scheduled `vlens-cli snapshot` run, Faz 10B) used to silently lose
// updates — both load the same starting array, both persist(.atomic)
// their own version, whichever finishes last wins and the other's write
// vanishes with no error anywhere. Found by an external code review. This
// fires many concurrent `add()` calls from separate tasks against one
// store/file and checks every single one survived.
@Test func concurrentAddsDoNotLoseWrites() async throws {
    let store = makeStore()
    let writerCount = 20

    await withTaskGroup(of: Void.self) { group in
        for i in 0..<writerCount {
            group.addTask {
                try? store.add(InventorySnapshot(vCenterHost: "vcenter.local", label: "writer-\(i)", metrics: makeMetrics()))
            }
        }
    }

    let loaded = store.loadAll()
    #expect(loaded.count == writerCount)
    let labels = Set(loaded.compactMap(\.label))
    #expect(labels.count == writerCount) // every writer's label present, none overwritten
}

// A file that exists but fails to decode (truncated write, disk corruption,
// a future incompatible format) must not be silently treated the same as
// "no snapshots yet" — that would let the next add()/delete() persist right
// over it, discarding whatever was actually in there. Found by an external
// code review alongside the concurrency issue (the two compound each other:
// a lost/interrupted concurrent write is exactly how a file ends up
// truncated mid-JSON in the first place).
@Test func addThrowsRatherThanOverwritingCorruptFile() throws {
    let store = makeStore()
    try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{ this is not valid JSON at all".utf8).write(to: store.url)

    #expect(throws: (any Error).self) {
        try store.add(InventorySnapshot(vCenterHost: "vcenter.local", label: "should not be saved", metrics: makeMetrics()))
    }

    // The corrupt file must be left exactly as it was — not overwritten
    // with a single-entry array.
    let rawAfter = try String(contentsOf: store.url, encoding: .utf8)
    #expect(rawAfter == "{ this is not valid JSON at all")
}

// loadAll() (the read path the GUI's snapshot list actually uses) is
// deliberately more forgiving than add()/delete() — showing an empty list
// beats refusing to render the tab at all over a corrupt file.
@Test func loadAllReturnsEmptyForCorruptFileRatherThanThrowing() throws {
    let store = makeStore()
    try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{ this is not valid JSON at all".utf8).write(to: store.url)

    #expect(store.loadAll().isEmpty)
}
