# Changelog

All notable changes to vLens are logged here, newest first. Each entry
corresponds to a merged PR. Format: `## [version] - date time (timezone)`.

## [1.5.4] - 2026-09-05 (+03)

### Added
- **vFloppy tab + Floppy connected vHealth rule** (RVTools #2, 17 of 24
  documented rules now implemented) — the last new device tab in this
  round of parity work. Per-VM floppy devices, read from the already-fetched
  `config.hardware.device` list (mirrors the existing vCD/vUSB tabs exactly,
  no extra collection round-trip). A connected floppy is flagged as a
  yellow vHealth finding, same pattern as the existing CDROM-connected
  rule. vcsim's default VMs never carry a floppy device, so this was
  verified structurally (`collectAll` returns a correctly-typed empty
  array, 10 VMs collected without error) rather than against a positive
  fixture — same limitation the vUSB/vPartition tabs already documented.

## [1.5.3] - 2026-09-05 (+03)

### Added
- **Certificate expiry vHealth rule** (RVTools #24, 16 of 24 documented
  rules now implemented) — warns when a host's own TLS certificate is
  within a configurable number of days of expiring (default 90, matching
  RVTools' own default), or flags it red if already expired. Adjustable in
  Preferences alongside the other vHealth thresholds. A host's certificate
  lives on a separate `CertificateManager` child object, not a plain
  `HostSystem` property — a real second, batched round trip per collection,
  not free like the other recent host-level rules; a host whose
  certificate can't be read (e.g. a permission restriction some
  environments apply) is silently skipped rather than failing the whole
  collection.

## [1.5.2] - 2026-09-05 (+03)

### Added
- **3 more vHealth rules** (RVTools #17/#20/#21, 15 of 24 documented rules
  now implemented): **ESXi Shell enabled** and **SSH enabled** — a plain
  warning when either management service is running on a host (`TSM`/
  `TSM-SSH`, confirmed against govmomi's own simulator fixtures). **NTP
  issue** — flags a host with no NTP servers configured at all, or one
  where servers are configured but the `ntpd` service isn't actually
  running (a real, common misconfiguration that config alone doesn't
  catch — a server list existing doesn't mean time is actually being
  synced). All three read directly off the same host property fetch
  `collectAll` already does (`config.service`, `config.dateTimeInfo`) — no
  extra vCenter round-trip.

## [1.5.1] - 2026-09-05 (+03)

### Added
- **2 more vHealth rules** (RVTools #22/#23, 12 of 24 documented rules now
  implemented): **Disk I/O performance tip** — a running VM with more than
  3 disks totaling over 750 GiB on fewer than 2 Paravirtual SCSI
  controllers funnels all that I/O through a single controller queue.
  **In-memory performance tip** — a running VM with 4+ vCPUs where CPU Hot
  Add, Memory Hot Add, or a single core per socket is configured can
  prevent virtual NUMA from being exposed to the guest, hurting
  memory-latency-sensitive workloads. RVTools' exact rule #23 also checks
  a `vnumaOnCpuHotaddExposed` VM setting, which isn't a documented,
  reliably-sourceable vim25 API property — left out rather than guessed
  at; the other three conditions are each real collected fields.

### Changed
- README's "historical performance trends" reworded — vPerformance
  reports avg/max for a chosen window, not a trend. Snapshot Compare's
  "VM Changes" section renamed to "VM Membership Changes" — it only ever
  reports added/removed VMs, never a field-by-field diff.

## [1.5.0] - 2026-09-05 (+03)

### Added
- **ESXi and vCenter end-of-life awareness** (GitHub issue #19, thanks
  [@yunusozturk](https://github.com/yunusozturk)). A new toolbar badge —
  shown only when at least one host or vCenter itself is nearing or past
  its VMware general-support end-of-life date — opens a popover listing
  each with Green/Orange/Red severity (Red: support has ended, Orange:
  ending within 180 days, a realistic ESXi/vCenter upgrade planning
  window). Sourced from endoflife.date's real public lifecycle data,
  matched against versions already collected — no extra vCenter call.
  Deliberately not its own sidebar tab (there's only ever one connected
  vCenter, and a tab that always shows exactly one row doesn't fit this
  app's "one row per real inventory item" pattern) and deliberately not
  folded into vHealth (which stays a pure, offline-data-only engine, same
  reasoning that already kept the security-advisory feature separate).
- **ESXi build number.** `HostInfo` now also collects the actual build
  (the same `AboutInfo.Build` field already read for vCenter, just
  host-scoped) — a VM's version alone can't be checked against a specific
  patch/advisory level. Shown appended to the vHost tab's "ESXi Version"
  column and as its own "ESXi Build" column in CSV/XLSX export.

## [1.4.3] - 2026-09-05 (+03)

### Changed
- **vSnapshot's "Size MiB" column now says what it doesn't include.**
  It's always been this snapshot's own data + memory file size,
  deliberately excluding the disk delta chain (attributing how much of a
  chain's cumulative size belongs to any one snapshot isn't well-defined
  without guessing) — every number was real, never estimated, but that
  caveat lived only in a code comment, not anywhere a user looking at the
  table would see it. The column header now reads "Size MiB (excl.
  deltas)" so a capacity decision made from this column alone isn't made
  on a false assumption of completeness.

## [1.4.2] - 2026-09-05 (+03)

### Fixed
- **Certificate pinning was still conditional on CA trust (critical).** The
  1.3.0 fix used govmomi's own `soap.Client.SetThumbprint`, which only ever
  consults the pinned fingerprint as a *fallback* — if the presented
  certificate happens to validate against the OS's own trust store for any
  reason, the connection succeeds without the thumbprint being checked at
  all. Confirmed directly: a deliberately wrong pinned fingerprint was
  rejected against an untrusted cert as expected, but accepted once that
  same cert was trusted via a CA, with the exact same wrong pin still
  configured. Fixed by not delegating to govmomi's dial logic at all: the
  transport's dialer now skips Go's chain verification entirely and
  unconditionally compares the presented certificate's SHA-256 thumbprint
  against the pinned one — an exact match is the only way to connect, no
  CA-trust escape hatch.
- **Disconnecting during an in-flight refresh could resurrect the
  connection**, and — with "Save this connection to Keychain" on — save
  whatever the password field had already been cleared to by
  `disconnect()`, overwriting the real saved password with an empty one.
  Both `performCollection` and `collectPerformance` now capture a
  connection "generation" before their network call and discard the
  result if a disconnect (or another connect/refresh) has since
  superseded it.
- **A new connection could silently overwrite a previously-selected saved
  profile.** Selecting a saved connection, disconnecting, then manually
  connecting somewhere else with "Save to Keychain" still on reused the
  first profile's id — since automation schedules pin a job to a profile
  by that same id, this could silently redirect a scheduled job too. Now
  only reuses the previous id when its stored host/username still match
  what's being connected; otherwise a fresh profile is created.
- **Snapshot writes proceeded without their cross-process lock if the lock
  itself couldn't be acquired** — the 1.3.0 fix for concurrent snapshot
  writes checked neither `open()`'s nor `flock()`'s failure, silently
  falling back to unlocked (and therefore unsafe) writes on exactly the
  kind of storage backend (a network share) most likely to hit that
  failure. Both failures now abort the write with an error instead.

All four found and verified by a second, independent round of review
(isolated tests against a delayed fake helper and real store instances,
`go test -race`, and a locked-out lock file) — not by inspection alone.

## [1.4.1] - 2026-09-05 (+03)

### Fixed
- **A scheduled automation job could silently run against the wrong
  connection.** `LaunchdScheduler` passed the saved connection's *name* to
  `vlens-cli`, even though the schedule itself stores a stable UUID — a
  name isn't guaranteed unique, and renaming a profile after scheduling it
  could point the job at nothing (or, in principle, at a same-named
  profile it was never meant to touch). The generated launchd job now
  passes `--profile-id <uuid>`, resolved by the CLI directly against that
  stable id.
- **"Scheduled and active" only checked that a plist file existed on disk**,
  not that launchd actually had the job loaded — a `bootstrap` that failed
  silently, or launchd's own database losing track of it, would still show
  as active. Preferences now asks launchd directly (`launchctl print`).
- **A scheduled job's last run result was invisible.** The job could be
  correctly loaded and still be silently failing every single time it
  fired (an expired password, a certificate that changed) with nothing in
  Preferences to show for it. `vlens-cli` now records the outcome of every
  automation-triggered run (success, or failure with the real error) and
  Preferences shows it.

Caught during this fix's own verification: recording that last-run result
requires a `UserDefaults` write to survive `vlens-cli` calling `exit()`
immediately afterward — without an explicit flush, a failed run's result
was silently lost, leaving whatever the previous *successful* run had
recorded. Found by testing the actual failure path live, not just the
happy path, against a real vcsim connection and a real `launchctl
bootstrap`/`bootout` cycle.

## [1.4.0] - 2026-09-05 (+03)

### Added
- **Refresh, Disconnect, and switching connections.** Previously the only
  way to get new data or connect somewhere else was quitting and
  relaunching the app. The toolbar now has a Refresh button (re-collects
  the current inventory) and a Disconnect button (returns to the connect
  screen, from which a different saved connection can be picked).
- **Stale data is now visible instead of silent.** If a refresh fails, the
  previously-collected data stays on screen — it's never cleared — but the
  status bar now shows "Refresh failed — data may be stale" (hover for the
  real error) instead of quietly leaving an old "Last refreshed" time as
  the only, easy-to-miss signal.
- **A snapshot now records when its data was actually collected, separately
  from when the snapshot itself was taken.** Taking a snapshot while
  showing stale data (a prior refresh had failed) used to timestamp it as
  if the data were as fresh as that instant — the Snapshots tab now flags
  such a snapshot and shows the real collection time on hover.

## [1.3.3] - 2026-09-05 (+03)

### Fixed
- **XLSX export silently converted text into numbers.** A cell's type used
  to be guessed from its value ("does this parse as a number?"), which
  mangled a VM literally named `00123` into the number `123` (the leading
  zero is gone) and a two-part version string like `8.0` into the number
  `8` — both real, unremarkable-looking data, not edge cases. Every column
  across every exportable model now declares its own type
  (`CSVExportable.xlsxColumnTypes`, text or number) instead of the value
  being sniffed at write time — CPU/RAM/capacity columns stay numeric,
  names/UUIDs/versions/IPs stay text regardless of what they look like.
  This also gives a future combined "export everything" a single already-
  declared source of truth for each column's type, rather than needing its
  own type-sniffing logic.

## [1.3.2] - 2026-09-05 (+03)

### Fixed
- **Performance collection could silently return a partial result.** A
  batched `QueryPerf` request failing partway through (a real vCenter
  timeout, a permissions gap, vcsim's limited counter support) used to
  degrade to whatever data had been gathered so far with no signal that
  anything was missing — indistinguishable from a genuinely complete,
  if small, result. The Go helper now reports a `performanceCoverage`
  (requested vs. collected VM count, `complete`, and the real error when
  incomplete) alongside every collection; vPerformance surfaces it as
  "Collected N of M VMs — the request failed partway through: ...".
- **A VM with multiple disks could have its IOPS metrics overwritten.**
  `virtualDisk.readIOSize.latest`/`writeIOSize.latest` return one series
  per disk instance — the code kept whichever disk's series it processed
  last, silently discarding the others' peaks. Now merges by taking the
  largest single-disk peak across all of a VM's disks.

Both were reproduced and fixed with new Go unit tests (`helper/main_test.go`,
this project's first) rather than only against vcsim, which doesn't support
per-disk IOPS counters at all — a first-batch failure, a later-batch
failure after some data was already collected, and the multi-disk merge are
each exercised directly with a fake performance sampler. The full-success
path was additionally confirmed live against vcsim.

## [1.3.1] - 2026-09-05 (+03)

### Fixed
- **CSV export was vulnerable to formula injection.** A cell starting with
  `=`, `+`, `-`, `@`, tab, or CR (e.g. a VM named `=cmd|'/c calc'!A1`) is
  interpreted as a formula by Excel/Numbers/Sheets when the file is opened —
  vCenter data is untrusted input. Such fields are now prefixed with a
  single quote (the standard OWASP mitigation), which displays literally
  without changing the field's value.
- **Every VM without a resolvable UUID got the same empty ID**, causing
  collisions in the GUI and exports. `mapVMInfo` set `VMUUID` directly from
  `vm.Config.Uuid` inside a guard that skipped it entirely when `Config`
  was nil; now uses the same `vmID()` fallback (real UUID, or the VM's own
  moref) every other per-VM mapper already used.
- **A real, healthy vCenter with zero VMs looked identical to "not
  connected."** The main window gated on `vms.isEmpty`, which a real
  environment satisfies as easily as never having connected — bouncing the
  user back to the connect screen instead of showing an empty inventory.
  Now tracked by a dedicated `isConnected` flag, set on a successful
  connection or demo load and cleared on exiting demo mode.
- **README described a pre-release, unnotarized, private project** — badge,
  status paragraph, and license line all predated this session's signing/
  notarization/Sparkle/public-repo work and had gone stale. Updated to
  reflect the real, current state (signed, notarized, public, five
  published GitHub releases).

### Changed
- Also fixes 4 of the 12 findings from the same external code review that
  produced 1.3.0's fixes (findings #6, #10, #12, plus the README
  inconsistency called out in its architectural commentary) — see that
  entry for the 4 critical fixes. The remaining P2 findings (refresh/
  disconnect UX, performance-collection partial failures, launchd/CLI
  profile resolution, XLSX numeric-conversion aggressiveness) remain
  backlog for a future pass.

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
