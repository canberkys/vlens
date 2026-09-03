import Foundation
import Testing
@testable import vLensCore

private func makeStore() -> HealthCheckPreferencesStore {
    let suiteName = "vLensTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return HealthCheckPreferencesStore(defaults: defaults)
}

@Test func loadWithNoSavedValuesReturnsDefaults() {
    let store = makeStore()
    let loaded = store.load()
    let defaults = HealthCheckThresholds()
    #expect(loaded == defaults)
}

@Test func saveThenLoadRoundTrips() {
    let store = makeStore()
    let custom = HealthCheckThresholds(datastoreFreeSpacePercent: 20, vCPUsPerCoreWarning: 6)

    store.save(custom)

    #expect(store.load() == custom)
}
