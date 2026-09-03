import SwiftUI
import vLensCore

/// Known tutorial/coachmark IDs — a new feature just adds a new constant
/// here and calls `.tutorialPopover(id:...)` once on its tab view. `all` is
/// what Preferences' "Reset tutorials" button clears.
///
/// Deliberately not on every tab: coachmarks are for tabs that are either
/// vLens' own invention (not from RVTools) or easily confused with a
/// similarly-named tab. A tab that's a direct, obviously-named RVTools
/// mirror (vInfo, vCPU, vDisk, ...) doesn't get one — an admin who knows
/// RVTools already knows what it does, and popovers on every tab would be
/// exactly the kind of nagging this feature is trying to avoid. When adding
/// a new tab, ask "would an RVTools-literate admin be confused by this one
/// specifically" before adding a coachmark for it.
enum TutorialID {
    static let onboardingWelcome = "onboarding.welcome"
    static let snapshots = "tutorial.snapshots"
    static let performance = "tutorial.performance"
    static let health = "tutorial.health"
    static let network = "tutorial.network"

    static let all = [onboardingWelcome, snapshots, performance, health, network]
}

extension View {
    /// Shows a one-time popover the first time this view appears, then
    /// never again (tracked in `TutorialStore`). Attach directly to a new
    /// feature's tab view — no other wiring needed.
    func tutorialPopover(id: String, title: String, text: String) -> some View {
        modifier(TutorialPopoverModifier(id: id, title: title, text: text))
    }
}

private struct TutorialPopoverModifier: ViewModifier {
    let id: String
    let title: String
    let text: String

    @State private var isPresented = false
    private let store = TutorialStore()

    func body(content: Content) -> some View {
        content
            .onAppear {
                if !store.hasSeen(id) {
                    isPresented = true
                }
            }
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Button("Got it") { isPresented = false }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(width: 260)
                .onDisappear { store.markSeen(id) }
            }
    }
}

/// First-run welcome — one dismissible card over the connect screen,
/// never shown again after that (see `TutorialID.onboardingWelcome`).
/// Deliberately not a multi-step slideshow — vLens' audience is technical/
/// pro users who'd rather get to Connect than click through slides.
struct WelcomeOverlayView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Welcome to vLens").font(.title2.bold())
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                bullet("sidebar.left", "Every tab lives in the sidebar, grouped by category.")
                bullet("play.circle", "No vCenter handy? Try Demo Mode below — it fills every tab with realistic mock data.")
                bullet("magnifyingglass", "The search box in the toolbar filters whatever tab you're looking at.")
            }

            Button("Got it") { onDismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 360)
    }

    private func bullet(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage).frame(width: 20)
            Text(text).font(.callout)
        }
    }
}
