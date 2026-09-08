import Foundation
import Testing
@testable import vLensCore

private func makeStore() -> EndOfLifePreferencesStore {
    let suiteName = "vLensTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return EndOfLifePreferencesStore(defaults: defaults)
}

@Test func endOfLifeEnabledByDefault() {
    let store = makeStore()
    #expect(store.isEnabled())
}

@Test func endOfLifeSettingDisabledPersists() {
    let store = makeStore()
    store.setEnabled(false)
    #expect(store.isEnabled() == false)
}

@Test func endOfLifeSettingEnabledAfterDisablingPersists() {
    let store = makeStore()
    store.setEnabled(false)
    store.setEnabled(true)
    #expect(store.isEnabled())
}
