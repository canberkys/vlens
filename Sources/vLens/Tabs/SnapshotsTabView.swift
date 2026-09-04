import SwiftUI
import vLensCore

private struct CompareRow: CSVExportable {
    let metric: String
    let baseline: String
    let current: String
    let delta: String

    static var csvHeader: [String] { ["Metric", "Baseline", "Current", "Delta"] }
    var csvRow: [String] { [metric, baseline, current, delta] }
}

/// Not an RVTools tab — this app's own "take a point-in-time record, compare
/// it against a later one" feature. Left side lists locally-persisted
/// history for the current vCenter host; right side compares any two of
/// them against `viewModel.enabledSnapshotMetricKeys` (configurable in
/// Preferences). See `ConnectionViewModel`'s Snapshots section and
/// `InventorySnapshotMetrics`.
struct SnapshotsTabView: View {
    @Bindable var viewModel: ConnectionViewModel
    let rows: [InventorySnapshot]

    @State private var newSnapshotLabel = ""
    @State private var includeFullDetail = false
    @State private var baselineID: UUID?
    @State private var currentID: UUID?
    @State private var pendingDeletion: InventorySnapshot?
    @State private var selectedSnapshotIDs: Set<UUID> = []
    @State private var pendingBulkDeletion = false

    var body: some View {
        HSplitView {
            snapshotList
                .frame(minWidth: 180, idealWidth: 260)
            comparePanel
                .frame(minWidth: 260, idealWidth: 360)
        }
        .onAppear(perform: syncDefaultSelection)
        .onChange(of: rows.count) { _, _ in syncDefaultSelection() }
        .tutorialPopover(
            id: TutorialID.snapshots, title: "Snapshots",
            text: "Not vSphere VM snapshots — this records a set of counts (VM/host/datastore counts, vHealth findings, etc.) so you can compare today against a later point in time. Take one now, then come back later to compare."
        )
    }

    private var snapshotList: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("Label (optional)", text: $newSnapshotLabel)
                    Button("Take Snapshot") {
                        viewModel.takeSnapshot(label: newSnapshotLabel.isEmpty ? nil : newSnapshotLabel, includeFullDetail: includeFullDetail)
                        newSnapshotLabel = ""
                    }
                }
                Toggle("Include full VM inventory", isOn: $includeFullDetail)
                    .toggleStyle(.checkbox)
                    .help("Also stores every VM's vInfo data with this snapshot, so Compare can show which VMs were added or removed — not just aggregate counts. Off by default: larger file, not needed for routine tracking.")
            }
            .padding(8)

            Divider()

            if rows.isEmpty {
                ContentUnavailableView(
                    "No snapshots yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Take a snapshot to start tracking this vCenter's inventory over time.")
                )
            } else {
                if !selectedSnapshotIDs.isEmpty {
                    HStack {
                        Text("\(selectedSnapshotIDs.count) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Deselect All") { selectedSnapshotIDs.removeAll() }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        Button(role: .destructive) {
                            pendingBulkDeletion = true
                        } label: {
                            Label("Delete Selected", systemImage: "trash")
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    Divider()
                }
                List(rows, selection: $selectedSnapshotIDs) { snapshot in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(snapshot.displayLabel).fontWeight(.medium)
                                if snapshot.fullVMList != nil {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .help("Includes full VM inventory")
                                }
                            }
                            Text(subtitle(for: snapshot))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            pendingDeletion = snapshot
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    // Fixed row height (rather than letting the 2-line
                    // label+subtitle stack size the row implicitly) — taking
                    // several snapshots in the same second (a real scenario
                    // once Faz 10's scheduler exists) triggered List's default
                    // insertion animation on multiple rows at once, which
                    // could catch a row mid-transition and render its trailing
                    // trash icon visibly clipped.
                    .frame(minHeight: 36)
                }
                .transaction { $0.disablesAnimations = true }
            }
        }
        .alert(
            "Delete this snapshot?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
        ) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                if let pendingDeletion {
                    selectedSnapshotIDs.remove(pendingDeletion.id)
                    viewModel.deleteSnapshot(pendingDeletion)
                }
                pendingDeletion = nil
            }
        } message: {
            if let pendingDeletion {
                Text("\"\(pendingDeletion.displayLabel)\" will be permanently removed. This can't be undone.")
            }
        }
        .alert(
            "Delete \(selectedSnapshotIDs.count) snapshots?",
            isPresented: $pendingBulkDeletion
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                viewModel.deleteSnapshots(ids: selectedSnapshotIDs)
                selectedSnapshotIDs.removeAll()
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    @ViewBuilder
    private var comparePanel: some View {
        if rows.count < 2 {
            ContentUnavailableView(
                "Need at least 2 snapshots",
                systemImage: "arrow.left.arrow.right",
                description: Text("Take another snapshot later to compare it against this one.")
            )
        } else {
            let baseline = rows.first(where: { $0.id == baselineID })
            let current = rows.first(where: { $0.id == currentID })

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Picker("Baseline", selection: $baselineID) {
                        ForEach(rows) { snapshot in
                            Text(snapshot.displayLabel).tag(Optional(snapshot.id))
                        }
                    }
                    Picker("Current", selection: $currentID) {
                        ForEach(rows) { snapshot in
                            Text(snapshot.displayLabel).tag(Optional(snapshot.id))
                        }
                    }

                    Button {
                        if let baseline, let current {
                            exportComparison(baseline: baseline, current: current)
                        }
                    } label: {
                        Label("Export Comparison", systemImage: "square.and.arrow.up")
                    }
                    .disabled(baseline == nil || current == nil)

                    Spacer()
                }
                .padding(8)

                Divider()

                if let baseline, let current {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            compareTable(baseline: baseline, current: current)
                            if let changes = vmChanges(baseline: baseline, current: current) {
                                vmChangesSection(changes)
                            }
                        }
                    }
                }
            }
        }
    }

    private struct VMChanges {
        let added: [String]
        let removed: [String]
    }

    /// `nil` unless **both** compared snapshots opted into "Include full VM
    /// inventory" — a snapshot taken without it simply can't answer "what
    /// changed," so the section doesn't appear rather than showing a
    /// misleadingly empty diff.
    private func vmChanges(baseline: InventorySnapshot, current: InventorySnapshot) -> VMChanges? {
        guard let baselineVMs = baseline.fullVMList, let currentVMs = current.fullVMList else { return nil }
        let baselineIDs = Set(baselineVMs.map(\.vmUUID))
        let currentIDs = Set(currentVMs.map(\.vmUUID))
        let added = currentVMs.filter { !baselineIDs.contains($0.vmUUID) }.map(\.name).sorted()
        let removed = baselineVMs.filter { !currentIDs.contains($0.vmUUID) }.map(\.name).sorted()
        return VMChanges(added: added, removed: removed)
    }

    private func vmChangesSection(_ changes: VMChanges) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VM Changes").fontWeight(.semibold).padding(.horizontal, 8).padding(.top, 12)
            if changes.added.isEmpty && changes.removed.isEmpty {
                Text("No VMs added or removed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            } else {
                if !changes.added.isEmpty {
                    vmChangeList(title: "Added (\(changes.added.count))", names: changes.added, color: .green, symbol: "plus.circle")
                }
                if !changes.removed.isEmpty {
                    vmChangeList(title: "Removed (\(changes.removed.count))", names: changes.removed, color: .red, symbol: "minus.circle")
                }
            }
        }
        .padding(.bottom, 12)
    }

    private func vmChangeList(title: String, names: [String], color: Color, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).fontWeight(.semibold).foregroundStyle(color).padding(.horizontal, 8)
            ForEach(names, id: \.self) { name in
                Label(name, systemImage: symbol)
                    .font(.callout)
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
            }
        }
    }

    /// CSV of exactly what the Compare panel shows (respecting
    /// `viewModel.enabledSnapshotMetricKeys`) — the generic tab-level Export
    /// menu only exports the raw snapshot list, not this synthesized
    /// baseline/current/delta view.
    private func exportComparison(baseline: InventorySnapshot, current: InventorySnapshot) {
        let descriptors = SnapshotMetricDescriptor.all.filter { viewModel.enabledSnapshotMetricKeys.contains($0.key) }
        let compareRows: [CompareRow] = descriptors.map { descriptor in
            let before = descriptor.value(baseline.metrics)
            let after = descriptor.value(current.metrics)
            return CompareRow(
                metric: descriptor.label,
                baseline: before.map(formatMetric) ?? "",
                current: after.map(formatMetric) ?? "",
                delta: deltaText(before: before, after: after)
            )
        }
        let filename = "\(sanitizedForFilename(baseline.displayLabel))-vs-\(sanitizedForFilename(current.displayLabel))-comparison.csv"
        ExportPanel.saveCSV(content: CSVWriter.write(compareRows), suggestedFilename: filename)
    }

    private func sanitizedForFilename(_ text: String) -> String {
        String(text.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    private func compareTable(baseline: InventorySnapshot, current: InventorySnapshot) -> some View {
        let descriptors = SnapshotMetricDescriptor.all.filter { viewModel.enabledSnapshotMetricKeys.contains($0.key) }

        return VStack(spacing: 0) {
            HStack {
                Text("Metric").fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                Text("Baseline").fontWeight(.semibold).frame(width: 90, alignment: .trailing)
                Text("Current").fontWeight(.semibold).frame(width: 90, alignment: .trailing)
                Text("Δ").fontWeight(.semibold).frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            Divider()

            ForEach(descriptors, id: \.key) { descriptor in
                let before = descriptor.value(baseline.metrics)
                let after = descriptor.value(current.metrics)
                HStack {
                    Text(descriptor.label).frame(maxWidth: .infinity, alignment: .leading)
                    Text(before.map(formatMetric) ?? "—").frame(width: 90, alignment: .trailing)
                    Text(after.map(formatMetric) ?? "—").frame(width: 90, alignment: .trailing)
                    Text(deltaText(before: before, after: after))
                        .foregroundStyle(deltaColor(before: before, after: after, direction: descriptor.direction))
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                Divider()
            }
        }
    }

    private func formatMetric(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private func deltaText(before: Double?, after: Double?) -> String {
        guard let before, let after else { return "—" }
        let delta = after - before
        guard delta != 0 else { return "±0" }
        return (delta > 0 ? "+" : "") + formatMetric(delta)
    }

    private func deltaColor(before: Double?, after: Double?, direction: MetricComparisonDirection) -> Color {
        guard let before, let after, after != before else { return .secondary }
        let improved = after > before
        switch direction {
        case .neutral: return .primary
        case .higherIsBetter: return improved ? .green : .red
        case .lowerIsBetter: return improved ? .red : .green
        }
    }

    /// When there's no custom label, `displayLabel` already shows the
    /// absolute timestamp as the title — repeating it here would just be
    /// noise (this is exactly the bug the user's screenshot caught: both
    /// lines showing the same "Sep 4, 2026 at 13:33"). Show a relative time
    /// instead; when there IS a custom label, the absolute time is new
    /// information, so keep it alongside the relative time.
    private func subtitle(for snapshot: InventorySnapshot) -> String {
        let relative = Self.relativeFormatter.localizedString(for: snapshot.takenAt, relativeTo: Date())
        guard let label = snapshot.label, !label.isEmpty else { return relative }
        return "\(snapshot.takenAt.formatted(date: .abbreviated, time: .shortened)) · \(relative)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    /// Defaults to comparing the two most recent snapshots — `rows` is
    /// already sorted newest-first by `ConnectionViewModel.loadSnapshotHistory`.
    private func syncDefaultSelection() {
        guard rows.count >= 2 else { return }
        if currentID == nil || !rows.contains(where: { $0.id == currentID }) {
            currentID = rows.first?.id
        }
        if baselineID == nil || !rows.contains(where: { $0.id == baselineID }) {
            baselineID = rows.dropFirst().first?.id
        }
    }
}
