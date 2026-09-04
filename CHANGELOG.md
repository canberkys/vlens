# Changelog

All notable changes to vLens are logged here, newest first. Each entry
corresponds to a merged PR. Format: `## [version] - date time (timezone)`.

## [1.1.3] - 2026-09-04 16:52 (+03)

### Added
- Snapshots tab: multi-select rows and delete several at once ("N
  selected" bar with Deselect All / Delete Selected, one confirmation for
  the whole batch) instead of only one-at-a-time via each row's trash
  button. `SnapshotStore` gained a batch `delete(ids:)` — one load/persist
  round trip for the whole selection instead of one per snapshot.

## [1.1.2] - 2026-09-04 16:42 (+03)

### Changed
- Connect screen redesigned again per a UI/UX audit's concrete feedback:
  one compact icon+title header instead of two stacked headlines, the
  saved-connections menu moved inline above the host field instead of
  floating as a standalone row, "Try demo mode" demoted below the primary
  Connect button instead of sharing its row, and the window shrunk from
  480×580 to 420×480 to match the now-tighter content instead of leaving
  it to expand into flexible spacers.

## [1.1.1] - 2026-09-04 16:32 (+03)

### Fixed
- Sidebar navigation could disappear entirely during an interactive window
  resize (reported live: take 2 snapshots, resize the window on the
  Snapshots tab). `NavigationSplitView` was left on system `.automatic`
  styling, which can silently collapse the sidebar into a hidden overlay
  under certain width conditions — and since this app's chrome isn't a
  real `.toolbar()`, none of SwiftUI's automatic sidebar-restore controls
  ever appeared, so there was no way back. Now binds `columnVisibility`
  explicitly to `.all`, forces `.navigationSplitViewStyle(.balanced)`, and
  adds a manual sidebar-toggle button as a safety net.

## [1.1.0] - 2026-09-04 16:15 (+03)

### Added
- Preferences → Automation: schedule a recurring snapshot or CSV/XLSX
  export (connection, action, day/time) that runs unattended via a real
  `launchd` agent calling `vlens-cli`. Requires a packaged `.app` build —
  `swift run` has no stable path for launchd to point at.
- `scripts/release.sh` now builds, signs, and bundles `vlens-cli` inside
  the `.app` (`Contents/MacOS/vlens-cli`) so scheduling has somewhere
  stable to run from.

### Changed
- Moved `ExportTab`/`ExportFormat`/`exportData` from the CLI target into
  `vLensCore` so the CLI and the new Automation tab picker share one list
  instead of two copies that could drift.
- Fixed a benign but noisy `UserDefaults` warning: `vlens-cli`, once
  bundled inside `vLens.app`, inherits the app's own bundle identifier, so
  the explicit shared-suite lookup added in 1.0.1 is now skipped when it
  would be a no-op (dev builds without a bundle ID still use it).
- Toolbar/banner no longer visibly shift position depending on the
  Snapshots tab's row count — the detail pane's content area is now
  explicitly pinned to fill available space top-down instead of centering
  based on its content's intrinsic height.

## [1.0.1] - 2026-09-04 15:54 (+03)

### Changed
- Connect screen redesigned: the real app icon now appears at the top with
  a one-line tagline, and the form is vertically balanced instead of
  sitting bottom-heavy in the window.
- About window now shows the real app icon instead of the placeholder SF
  Symbol graphic used since the Faz 3 signing work.

## [1.0.0] - 2026-09-04

- First signed, notarized release. See the
  [v1.0.0 GitHub Release](https://github.com/canberkys/vlens/releases/tag/v1.0.0)
  notes for the full feature list.
