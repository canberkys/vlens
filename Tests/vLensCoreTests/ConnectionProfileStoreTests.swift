import Foundation
import Testing
@testable import vLensCore

private func makeStore() -> ConnectionProfileStore {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vLensTests-\(UUID().uuidString)", isDirectory: true)
    return ConnectionProfileStore(fileURL: dir.appendingPathComponent("connection-profiles.json"))
}

@Test func loadAllOnMissingFileReturnsEmpty() {
    let store = makeStore()
    #expect(store.loadAll().isEmpty)
}

@Test func upsertThenLoadRoundTrips() throws {
    let store = makeStore()
    let profile = ConnectionProfile(name: "vcenter.local", host: "vcenter.local", username: "admin")

    try store.upsert(profile)

    let loaded = store.loadAll()
    #expect(loaded.count == 1)
    #expect(loaded[0].id == profile.id)
    #expect(loaded[0].host == "vcenter.local")
}

@Test func upsertWithSameIDReplacesRatherThanDuplicates() throws {
    let store = makeStore()
    let id = UUID()
    try store.upsert(ConnectionProfile(id: id, name: "old-name", host: "vcenter.local", username: "admin"))
    try store.upsert(ConnectionProfile(id: id, name: "new-name", host: "vcenter.local", username: "admin"))

    let loaded = store.loadAll()
    #expect(loaded.count == 1)
    #expect(loaded[0].name == "new-name")
}

@Test func deleteRemovesOnlyTheMatchingProfile() throws {
    let store = makeStore()
    let keep = ConnectionProfile(name: "keep", host: "a", username: "u")
    let remove = ConnectionProfile(name: "remove", host: "b", username: "u")
    try store.upsert(keep)
    try store.upsert(remove)

    try store.delete(id: remove.id)

    let loaded = store.loadAll()
    #expect(loaded.count == 1)
    #expect(loaded[0].id == keep.id)
}
