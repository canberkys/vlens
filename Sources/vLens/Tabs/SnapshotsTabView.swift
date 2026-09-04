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
    @State private var baselineID: UUID?
    @State private var currentID: UUID?

    var body: some View {
        HSplitView {
            snapshotList
                .frame(minWidth: 260, idealWidth: 300)
            comparePanel
                .frame(minWidth: 420)
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
            HStack {
                TextField("Label (optional)", text: $newSnapshotLabel)
                Button("Take Snapshot") {
                    viewModel.takeSnapshot(label: newSnapshotLabel.isEmpty ? nil : newSnapshotLabel)
                    newSnapshotLabel = ""
                }
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
                List(rows) { snapshot in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.displayLabel).fontWeight(.medium)
                            Text(subtitle(for: snapshot))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.deleteSnapshot(snapshot)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
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
                    compareTable(baseline: baseline, current: current)
                }
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

        return ScrollView {
            VStack(spacing: 0) {
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
