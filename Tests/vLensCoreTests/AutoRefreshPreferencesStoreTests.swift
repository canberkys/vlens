import Foundation
import Testing
@testable import vLensCore

private func makeStore() -> AutoRefreshPreferencesStore {
    let suiteName = "vLensTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return AutoRefreshPreferencesStore(defaults: defaults)
}

@Test func autoRefreshDisabledByDefault() {
    let store = makeStore()
    #expect(store.isEnabled() == false)
}

@Test func autoRefreshDefaultIntervalIsFiveMinutes() {
    let store = makeStore()
    #expect(store.intervalMinutes() == 5)
}

@Test func autoRefreshSettingEnabledPersists() {
    let store = makeStore()
    store.setEnabled(true)
    #expect(store.isEnabled())
}

@Test func autoRefreshSettingIntervalPersists() {
    let store = makeStore()
    store.setIntervalMinutes(30)
    #expect(store.intervalMinutes() == 30)
}
