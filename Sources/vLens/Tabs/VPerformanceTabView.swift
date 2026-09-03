import SwiftUI
import vLensCore

/// The one tab whose data isn't part of `collectAll` — it has its own
/// time-window picker and refresh control, wired to
/// `ConnectionViewModel.collectPerformance(intervalMinutes:)` rather than
/// the shared connect/refresh flow. See that method's doc comment.
struct VPerformanceTabView: View {
    @Bindable var viewModel: ConnectionViewModel
    let rows: [VMPerformanceInfo]

    @State private var selectedIntervalMinutes = 60
    @State private var sortOrder = [FieldComparator<VMPerformanceInfo>.value("vm", \.vmName)]

    private let intervals: [(label: String, minutes: Int)] = [
        ("1 hour", 60), ("4 hours", 240), ("24 hours", 1440), ("7 days", 10080), ("30 days", 43200)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Window", selection: $selectedIntervalMinutes) {
                    ForEach(intervals, id: \.minutes) { interval in
                        Text(interval.label).tag(interval.minutes)
                    }
                }
                .frame(width: 180)

                Button {
                    Task { await viewModel.collectPerformance(intervalMinutes: selectedIntervalMinutes) }
                } label: {
                    if viewModel.isCollectingPerformance {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Collect", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isCollectingPerformance)

                if let error = viewModel.performanceErrorMessage {
                    Text(error).foregroundStyle(.red).lineLimit(1)
                }

                Spacer()
            }
            .padding(8)

            Divider()

            if rows.isEmpty {
                ContentUnavailableView(
                    "No performance data",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Choose a time window and press Collect. Only powered-on VMs report performance samples.")
                )
            } else {
                Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
                    TableColumn("VM", sortUsing: FieldComparator.value("vm", \.vmName)) { Text($0.vmName) }
                    TableColumn("Avg CPU %", sortUsing: FieldComparator.optional("avgCpu", \.avgCpuUsagePercent)) { row in
                        Text(row.avgCpuUsagePercent.map { String(format: "%.1f", $0) } ?? "—")
                    }
                    TableColumn("Max CPU %", sortUsing: FieldComparator.optional("maxCpu", \.maxCpuUsagePercent)) { row in
                        Text(row.maxCpuUsagePercent.map { String(format: "%.1f", $0) } ?? "—")
                    }
                    TableColumn("Avg RAM %", sortUsing: FieldComparator.optional("avgRam", \.avgRamUsagePercent)) { row in
                        Text(row.avgRamUsagePercent.map { String(format: "%.1f", $0) } ?? "—")
                    }
                    TableColumn("Max RAM %", sortUsing: FieldComparator.optional("maxRam", \.maxRamUsagePercent)) { row in
                        Text(row.maxRamUsagePercent.map { String(format: "%.1f", $0) } ?? "—")
                    }
                    TableColumn("Max Read IO", sortUsing: FieldComparator.optional("readIO", \.maxReadIOSizeBytes)) { row in
                        Text(row.maxReadIOSizeBytes.map { "\($0) B" } ?? "—")
                    }
                    TableColumn("Max Write IO", sortUsing: FieldComparator.optional("writeIO", \.maxWriteIOSizeBytes)) { row in
                        Text(row.maxWriteIOSizeBytes.map { "\($0) B" } ?? "—")
                    }
                }
            }
        }
        .tutorialPopover(
            id: TutorialID.performance, title: "vPerformance",
            text: "Historical CPU/RAM/disk-IO usage over a time window you choose — unlike every other tab, which shows an instantaneous value. Pick a window and press Collect; only powered-on VMs report samples."
        )
    }
}
