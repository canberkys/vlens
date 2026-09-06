import AppKit
import SwiftUI
import vLensCore

/// vLens' equivalent of RVTools' Health Properties panel. Lives in the
/// standard macOS Settings scene (Cmd+,), sharing the same
/// `ConnectionViewModel` instance as the main window so a threshold change
/// re-evaluates vHealth immediately against whatever's already collected.
struct PreferencesView: View {
    @Bindable var viewModel: ConnectionViewModel

    private enum AutomationActionKind: Hashable {
        case snapshot, exportCSV, exportXLSX
    }

    @State private var automationEnabled = false
    @State private var automationProfileID: UUID?
    @State private var automationActionKind: AutomationActionKind = .snapshot
    @State private var automationFullDetail = false
    @State private var automationTab: ExportTab = .vinfo
    @State private var automationWeekday = 2 // Monday
    @State private var automationTime = Date()

    var body: some View {
        Form {
            Section("vHealth thresholds") {
                LabeledContent("Datastore free space warning") {
                    HStack(spacing: 4) {
                        TextField(
                            "",
                            value: clampedThreshold(\.datastoreFreeSpacePercent, in: 0...100),
                            format: .number
                        )
                        .frame(width: 50)
                        .multilineTextAlignment(.trailing)
                        Text("%")
                    }
                }
                Text("Flags a datastore when free space drops below this percentage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("vCPUs per core warning") {
                    TextField(
                        "",
                        value: clampedThreshold(\.vCPUsPerCoreWarning, in: 0.1...1000),
                        format: .number
                    )
                    .frame(width: 50)
                    .multilineTextAlignment(.trailing)
                }
                Text("Flags a host when active vCPUs per physical core exceeds this ratio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Guest disk free space warning") {
                    HStack(spacing: 4) {
                        TextField(
                            "",
                            value: clampedThreshold(\.guestDiskFreeSpacePercent, in: 0...100),
                            format: .number
                        )
                        .frame(width: 50)
                        .multilineTextAlignment(.trailing)
                        Text("%")
                    }
                }
                Text("Flags a guest partition (vPartition) when free space drops below this percentage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Max VMs per datastore") {
                    TextField(
                        "",
                        value: clampedThreshold(\.maxVMsPerDatastore, in: 1...9999),
                        format: .number
                    )
                    .frame(width: 50)
                    .multilineTextAlignment(.trailing)
                }
                Text("Flags a datastore when the number of registered VMs on it exceeds this count.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Certificate expiry warning") {
                    HStack(spacing: 4) {
                        TextField(
                            "",
                            value: clampedThreshold(\.certificateExpiryWarningDays, in: 0...3650),
                            format: .number
                        )
                        .frame(width: 50)
                        .multilineTextAlignment(.trailing)
                        Text("days")
                    }
                }
                Text("Flags a host's certificate when it expires within this many days, or has already expired.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Reset to Defaults") {
                    viewModel.healthCheckThresholds = HealthCheckThresholds()
                }
                .font(.caption)
            }

            Section("Privacy") {
                Toggle("Check for VMware security advisories", isOn: $viewModel.securityAdvisoriesEnabled)
                Text("Fetches Broadcom's public security advisory list once per launch — a plain internet request, independent of any vCenter connection. Off skips this entirely.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Snapshot comparison metrics") {
                Text("Which rows the Snapshots tab's Compare panel shows. Every metric is always recorded — this only controls what's displayed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Select All") {
                        viewModel.enabledSnapshotMetricKeys = Set(SnapshotMetricDescriptor.all.map(\.key))
                    }
                    Button("Select None") {
                        viewModel.enabledSnapshotMetricKeys = []
                    }
                }
                .font(.caption)
                ForEach(SnapshotMetricDescriptor.all, id: \.key) { descriptor in
                    HStack(spacing: 4) {
                        Toggle(descriptor.label, isOn: Binding(
                            get: { viewModel.enabledSnapshotMetricKeys.contains(descriptor.key) },
                            set: { isOn in
                                if isOn {
                                    viewModel.enabledSnapshotMetricKeys.insert(descriptor.key)
                                } else {
                                    viewModel.enabledSnapshotMetricKeys.remove(descriptor.key)
                                }
                            }
                        ))
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .help(descriptor.helpText)
                    }
                }
            }

            Section("Snapshot storage") {
                LabeledContent("Location") {
                    Text(viewModel.snapshotStorageURL.deletingLastPathComponent().path)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([viewModel.snapshotStorageURL])
                    }
                    Button("Change Location…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.prompt = "Choose"
                        if panel.runModal() == .OK, let url = panel.url {
                            viewModel.changeSnapshotStorageDirectory(to: url)
                        }
                    }
                    if viewModel.snapshotStorageURL.deletingLastPathComponent() != SnapshotStore.defaultDirectory {
                        Button("Reset to Default") {
                            viewModel.changeSnapshotStorageDirectory(to: nil)
                        }
                    }
                }
                Text("Where inventory-snapshots.json is stored — useful for pointing it at a shared folder. Switching copies the existing file to the new location; the old one is left in place.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Saved connections") {
                if viewModel.savedProfiles.isEmpty {
                    Text("Connections saved from the connect screen (\"Save this connection to Keychain\") show up here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.savedProfiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                Text("\(profile.username)@\(profile.host)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.automationSchedule?.profileID == profile.id {
                                Image(systemName: "clock.badge.exclamationmark")
                                    .foregroundStyle(.orange)
                                    .help("Used by the Automation schedule below — deleting it will break that schedule.")
                            }
                            Button(role: .destructive) {
                                viewModel.deleteSavedProfile(profile)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .help("Delete saved connection")
                            .accessibilityLabel("Delete saved connection \(profile.name)")
                        }
                    }
                }
            }

            Section("Automation") {
                if viewModel.savedProfiles.isEmpty {
                    Text("Save a connection (with \"Save this connection to Keychain\" enabled) to schedule automated snapshots or exports.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Toggle("Enable scheduled automation", isOn: $automationEnabled)

                    Picker("Connection", selection: $automationProfileID) {
                        ForEach(viewModel.savedProfiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    .disabled(!automationEnabled)

                    Picker("Action", selection: $automationActionKind) {
                        Text("Take Snapshot").tag(AutomationActionKind.snapshot)
                        Text("Export CSV").tag(AutomationActionKind.exportCSV)
                        Text("Export XLSX").tag(AutomationActionKind.exportXLSX)
                    }
                    .disabled(!automationEnabled)

                    if automationActionKind == .snapshot {
                        Toggle("Include full VM inventory", isOn: $automationFullDetail)
                            .disabled(!automationEnabled)
                    } else {
                        Picker("Tab", selection: $automationTab) {
                            ForEach(ExportTab.allCases, id: \.self) { tab in
                                Text(tab.label).tag(tab)
                            }
                        }
                        .disabled(!automationEnabled)
                    }

                    Picker("Day", selection: $automationWeekday) {
                        ForEach(1...7, id: \.self) { day in
                            Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                        }
                    }
                    .disabled(!automationEnabled)

                    DatePicker("Time", selection: $automationTime, displayedComponents: .hourAndMinute)
                        .disabled(!automationEnabled)

                    HStack {
                        Button("Save") { saveAutomation() }
                            .disabled(automationEnabled && automationProfileID == nil)
                        if viewModel.automationSchedule != nil {
                            Button("Remove", role: .destructive) {
                                viewModel.removeAutomationSchedule()
                                automationEnabled = false
                            }
                        }
                    }

                    if let error = viewModel.automationError {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }

                    if let schedule = viewModel.automationSchedule, schedule.enabled {
                        Label(
                            LaunchdScheduler.isActuallyLoaded ? "Scheduled and active" : "Not active — see error above",
                            systemImage: LaunchdScheduler.isActuallyLoaded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(LaunchdScheduler.isActuallyLoaded ? .green : .orange)
                        .font(.caption)

                        if let lastRun = AutomationPreferencesStore().loadLastRunResult() {
                            Label(
                                "Last run \(lastRun.ranAt.formatted(date: .abbreviated, time: .shortened)): "
                                    + (lastRun.succeeded ? "succeeded" : "failed" + (lastRun.message.map { " (\($0))" } ?? "")),
                                systemImage: lastRun.succeeded ? "checkmark.circle" : "xmark.octagon.fill"
                            )
                            .foregroundStyle(lastRun.succeeded ? Color.secondary : Color.red)
                            .font(.caption)
                        }
                    }

                    Text("Runs vlens-cli in the background at the scheduled time via launchd — only works from a packaged .app build (a stable path launchd can point at), not swift run.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tutorials") {
                Button("Reset Tutorials") {
                    TutorialStore().resetAll(ids: TutorialID.all)
                }
                Text("Shows the welcome screen and per-feature tips again — they only appear once on their own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 960)
        .onAppear(perform: syncAutomationForm)
    }

    /// Wraps one `HealthCheckThresholds` field in a `Binding` that clamps
    /// on write — a `TextField` bound directly to the raw value happily
    /// accepts a negative percentage or a zero VM count, both nonsensical
    /// for their domain (see the ranges each call site passes). Reassigns
    /// the whole `healthCheckThresholds` struct so `ConnectionViewModel`'s
    /// existing `didSet` (persist + re-evaluate vHealth) still fires.
    private func clampedThreshold<T: Comparable>(
        _ keyPath: WritableKeyPath<HealthCheckThresholds, T>, in range: ClosedRange<T>
    ) -> Binding<T> {
        Binding(
            get: { viewModel.healthCheckThresholds[keyPath: keyPath] },
            set: { newValue in
                var thresholds = viewModel.healthCheckThresholds
                thresholds[keyPath: keyPath] = min(max(newValue, range.lowerBound), range.upperBound)
                viewModel.healthCheckThresholds = thresholds
            }
        )
    }

    private func syncAutomationForm() {
        guard let schedule = viewModel.automationSchedule else {
            automationProfileID = viewModel.savedProfiles.first?.id
            return
        }
        automationEnabled = schedule.enabled
        automationProfileID = schedule.profileID
        switch schedule.action {
        case .snapshot(let fullDetail):
            automationActionKind = .snapshot
            automationFullDetail = fullDetail
        case .export(let tab, let format):
            automationActionKind = format == .csv ? .exportCSV : .exportXLSX
            automationTab = tab
        }
        automationWeekday = schedule.weekday
        var components = DateComponents()
        components.hour = schedule.hour
        components.minute = schedule.minute
        automationTime = Calendar.current.date(from: components) ?? Date()
    }

    private func saveAutomation() {
        guard let profileID = automationProfileID else { return }
        let action: AutomationAction = switch automationActionKind {
        case .snapshot: .snapshot(fullDetail: automationFullDetail)
        case .exportCSV: .export(tab: automationTab, format: .csv)
        case .exportXLSX: .export(tab: automationTab, format: .xlsx)
        }
        let time = Calendar.current.dateComponents([.hour, .minute], from: automationTime)
        let schedule = AutomationSchedule(
            enabled: automationEnabled, profileID: profileID, action: action,
            weekday: automationWeekday, hour: time.hour ?? 9, minute: time.minute ?? 0
        )
        viewModel.saveAutomationSchedule(schedule)
    }
}

#Preview {
    PreferencesView(viewModel: ConnectionViewModel())
}
