# Changelog

All notable changes to vLens are logged here, newest first. Each entry
corresponds to a merged PR. Format: `## [version] - date time (timezone)`.

## [1.3.0] - 2026-09-05 (+03)

### Fixed
- **Packaged app crashed on launch on any Mac other than the one it was
  built on.** SwiftPM's generated resource bundle accessor (`Bundle.module`)
  was never actually copied into the `.app` by `scripts/release.sh` — its
  only fallback was an absolute path into the build machine's own
  `.build/` directory, so every prior release crashed with a `fatalError`
  for anyone who downloaded it. Fixed by copying the resource bundle into
  the conventional `Contents/Resources/` location (a new
  `AppResourceLocator.swift` looks there first, falling back to
  `Bundle.module` for unsigned dev builds) — `Contents/` is required
  because `codesign` rejects anything placed at the `.app` bundle root.
- **Certificate pinning wasn't actually binding the real data connection.**
  The trust-on-first-use fingerprint was verified against one throwaway
  TLS probe, but the actual credentialed session (inventory collection,
  performance collection) connected with `insecure: true` and no link to
  that fingerprint — a MITM able to pass the first check could still
  intercept the second. Now uses govmomi's own thumbprint-pinning
  mechanism (`soap.Client.SetThumbprint`) so the real connection fails
  closed unless its certificate matches the one the user approved.
- **A healthy multipath was always flagged red.** The health check
  compared `ScsiLun.OperationalState` (LUN-level values like `"ok"`/
  `"degraded"`) against the vocabulary for per-path state
  (`"active"`/`"standby"`) — every LUN reporting its normal `"ok"` state
  failed the rule. Now checks for the correct LUN-level vocabulary.
- **Snapshot writes could race and silently lose data.** The GUI and a
  scheduled `vlens-cli` run could both read-modify-write
  `inventory-snapshots.json` at once with no coordination, and a corrupt
  file was silently treated as empty on the next write. Added
  cross-process file locking (`flock`) around every write, and mutation
  now fails loudly on an unreadable file instead of overwriting it
  (read-only display still degrades gracefully to an empty list).
- **Real helper errors were discarded on failure.** The Go helper writes
  a descriptive JSON error to stdout even on failure, but the Swift
  client only read stderr — surfacing a generic, unhelpful message.
  Now decodes stdout first and only falls back to stderr if that fails.

Found by an external code review of the full codebase; each fix was
verified against live behavior (a real crash reproduction, a real vcsim
connection, live vcsim TLS probes with correct/incorrect/missing
fingerprints, and concurrent-write stress tests) rather than just
compiling cleanly.

## [1.2.3] - 2026-09-05 (+03)

### Fixed
- Help ▸ What's New rendered poorly — dumping the whole `CHANGELOG.md`
  through Foundation's `AttributedString(markdown:)` into a single `Text`
  applied no heading/list visual hierarchy at all. Now parsed by hand into
  per-version, per-section views (proper title sizing, bullet spacing)
  matching the rest of Help's styling; inline `**bold**`/`` `code` ``
  within a bullet still uses the native Markdown parser, which handles
  that narrower case well.

## [1.2.2] - 2026-09-05 (+03)

### Added
- Help ▸ What's New: the full changelog, right in the app, rendered from
  the same `CHANGELOG.md` that ships with every release.
- Sparkle's update dialog now shows that release's notes inline (pulled
  from `CHANGELOG.md` at release time) instead of just a bare version
  number — no separate popup, it's part of the update prompt you already see.

## [1.2.1] - 2026-09-05 (+03)

### Added
- Preferences → Snapshot comparison metrics: "Select All" / "Select None"
  instead of only toggling each of the 11 metrics one at a time.

## [1.2.0] - 2026-09-04 17:10 (+03)

### Added
- Automatic update checks via Sparkle — vLens now checks a public appcast
  feed on a schedule (and via a new "Check for Updates…" menu item) and
  shows Sparkle's own native update sheet when a newer signed build is
  available. Updates are EdDSA-signed (`sign_update`/`generate_keys`) —
  the private key never leaves this machine's Keychain.
- `scripts/release.sh` now embeds and signs `Sparkle.framework` inside the
  `.app` (inside-out nested signing: Autoupdate, Updater.app, two XPC
  services, then the framework itself) and writes `appcast.xml` with the
  new release's EdDSA signature after packaging the DMG.

### Changed
- **The `vLens` repository is now public.** Sparkle's background update
  check can't carry authentication, so the appcast feed and release
  assets need to be reachable from a plain, unauthenticated HTTPS request
  — not possible from a private repo. Commit history was checked first;
  no credentials or secrets were ever committed.

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
