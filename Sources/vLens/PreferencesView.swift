import AppKit
import SwiftUI
import vLensCore

/// vLens' equivalent of RVTools' Health Properties panel. Lives in the
/// standard macOS Settings scene (Cmd+,), sharing the same
/// `ConnectionViewModel` instance as the main window so a threshold change
/// re-evaluates vHealth immediately against whatever's already collected.
struct PreferencesView: View {
    @Bindable var viewModel: ConnectionViewModel

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
        .frame(width: 460, height: 720)
    }
}

#Preview {
    PreferencesView(viewModel: ConnectionViewModel())
}
