import Foundation
import Testing
@testable import vLensCore

private func makeStore() -> TutorialStore {
    let suiteName = "vLensTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return TutorialStore(defaults: defaults)
}

@Test func hasNotSeenByDefault() {
    let store = makeStore()
    #expect(store.hasSeen("onboarding.welcome") == false)
}

@Test func markSeenPersists() {
    let store = makeStore()
    store.markSeen("onboarding.welcome")
    #expect(store.hasSeen("onboarding.welcome"))
}

@Test func markingOneIDDoesNotAffectAnother() {
    let store = makeStore()
    store.markSeen("tutorial.snapshots")
    #expect(store.hasSeen("tutorial.performance") == false)
}

@Test func resetAllClearsOnlyGivenIDs() {
    let store = makeStore()
    store.markSeen("onboarding.welcome")
    store.markSeen("tutorial.snapshots")

    store.resetAll(ids: ["onboarding.welcome", "tutorial.snapshots"])

    #expect(store.hasSeen("onboarding.welcome") == false)
    #expect(store.hasSeen("tutorial.snapshots") == false)
}
