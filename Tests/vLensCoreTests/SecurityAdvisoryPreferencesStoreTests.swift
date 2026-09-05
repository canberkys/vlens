import Foundation
import Testing
@testable import vLensCore

private func makeStore() -> SecurityAdvisoryPreferencesStore {
    let suiteName = "vLensTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return SecurityAdvisoryPreferencesStore(defaults: defaults)
}

@Test func securityAdvisoriesEnabledByDefault() {
    let store = makeStore()
    #expect(store.isEnabled())
}

@Test func settingDisabledPersists() {
    let store = makeStore()
    store.setEnabled(false)
    #expect(store.isEnabled() == false)
}

@Test func settingEnabledAfterDisablingPersists() {
    let store = makeStore()
    store.setEnabled(false)
    store.setEnabled(true)
    #expect(store.isEnabled())
}
