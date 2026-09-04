import SwiftUI
import AppKit
import Sparkle

@main
struct vLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Owned here, not inside ContentView, so the Settings scene
    // (Cmd+,/PreferencesView) can share the same instance — changing a
    // threshold there needs to re-evaluate vHealth on the data already
    // sitting in the main window, not a separate copy of it.
    @State private var viewModel = ConnectionViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
        .commands {
            // Replaces the default About panel — in `swift run` dev mode
            // there's no real Info.plist for it to read from, so it shows
            // blank; this always shows correct info (see AppVersion).
            CommandGroup(replacing: .appInfo) {
                Button("About vLens") {
                    openWindow(id: "about")
                }
                Button("Check for Updates…") {
                    appDelegate.updaterController.checkForUpdates(nil)
                }
            }
            // Replaces the default (empty) Help menu item — native in-app
            // help, not a link out to an external site.
            CommandGroup(replacing: .help) {
                Button("vLens Help") {
                    openWindow(id: "help")
                }
                .keyboardShortcut("?", modifiers: [.command, .shift])

                Button("Send Feedback…") {
                    openWindow(id: "feedback")
                }
            }
        }

        Window("About vLens", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("vLens Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)

        Window("vLens Feedback", id: "feedback") {
            FeedbackView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)

        Settings {
            PreferencesView(viewModel: viewModel)
        }
    }
}

/// `swift run` launches vLens as a bare process, not a Finder-opened .app
/// bundle, so macOS doesn't automatically hand it keyboard focus — the
/// window can appear in front while keystrokes still go to the terminal
/// that launched it. Force activation on launch so this stays a non-issue
/// during development; a real notarized .app bundle won't need this.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `startingUpdater: true` begins Sparkle's own background schedule
    /// immediately (per `SUScheduledCheckInterval`/`SUEnableAutomaticChecks`
    /// in `Resources/Info.plist`) — silent unless it actually finds a newer
    /// version, at which point it shows its own native update sheet.
    /// `swift run`/dev builds have no real Info.plist (no `SUFeedURL`), so
    /// this silently no-ops there rather than erroring — only meaningful in
    /// a packaged, signed `.app`.
    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
