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
                            value: $viewModel.healthCheckThresholds.datastoreFreeSpacePercent,
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
                        value: $viewModel.healthCheckThresholds.vCPUsPerCoreWarning,
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
                            value: $viewModel.healthCheckThresholds.guestDiskFreeSpacePercent,
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
                        value: $viewModel.healthCheckThresholds.maxVMsPerDatastore,
                        format: .number
                    )
                    .frame(width: 50)
                    .multilineTextAlignment(.trailing)
                }
                Text("Flags a datastore when the number of registered VMs on it exceeds this count.")
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
                            LaunchdScheduler.isInstalled ? "Scheduled and active" : "Not active — see error above",
                            systemImage: LaunchdScheduler.isInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(LaunchdScheduler.isInstalled ? .green : .orange)
                        .font(.caption)
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
        .frame(width: 460, height: 860)
        .onAppear(perform: syncAutomationForm)
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
