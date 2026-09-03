import SwiftUI
import Charts
import vLensCore

/// Snapshot of exactly what `ReportView` needs, assembled once at
/// "Generate Report" time — deliberately not a live binding to
/// `ConnectionViewModel`, since a PDF render should reflect one fixed
/// moment, not whatever the view model happens to hold when `ImageRenderer`
/// gets around to drawing.
struct ReportData {
    let vCenterHost: String
    let vCenterInfo: VCenterInfo?
    let vms: [VirtualMachineInfo]
    let hosts: [HostInfo]
    let clusters: [ClusterInfo]
    let datastores: [DatastoreInfo]
    let healthChecks: [HealthCheckResult]
    let generatedAt: Date
}

/// A curated, management-facing summary — not a data export (that's CSV/XLSX's
/// job, see `docs/vLens-Reference.md` §6). Rendered to a single, dynamically-
/// sized PDF page via `ImageRenderer` (`ReportRenderer.renderPDF`), no
/// pagination — this is a one-pager by design, not a full inventory dump.
struct ReportView: View {
    let data: ReportData

    private var poweredOn: Int { data.vms.filter { $0.powerState == .poweredOn }.count }
    private var poweredOff: Int { data.vms.filter { $0.powerState == .poweredOff }.count }
    private var suspended: Int { data.vms.count - poweredOn - poweredOff }
    private var totalCapacityMiB: Int { data.datastores.reduce(0) { $0 + $1.capacityMiB } }
    private var totalFreeMiB: Int { data.datastores.reduce(0) { $0 + $1.freeMiB } }
    private var overallFreePercent: Double {
        guard totalCapacityMiB > 0 else { return 0 }
        return Double(totalFreeMiB) / Double(totalCapacityMiB) * 100
    }
    private var redCount: Int { data.healthChecks.filter { $0.severity == .red }.count }
    private var yellowCount: Int { data.healthChecks.filter { $0.severity == .yellow }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            statCards
            HStack(alignment: .top, spacing: 24) {
                powerStateChart
                datastoreChart
            }
            healthSummary
            Spacer(minLength: 0)
            footer
        }
        .padding(32)
        .frame(width: 760)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(data.vCenterHost)
                .font(.system(size: 26, weight: .bold))
            if let info = data.vCenterInfo {
                Text("\(info.fullName) · Build \(info.build)")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.black.opacity(0.6))
            }
            Text("vLens Infrastructure Report — generated \(data.generatedAt.formatted(date: .long, time: .shortened))")
                .font(.system(size: 12))
                .foregroundStyle(Color.black.opacity(0.5))
        }
    }

    private var statCards: some View {
        HStack(spacing: 16) {
            statCard(title: "Virtual Machines", value: "\(data.vms.count)", detail: "\(poweredOn) on · \(poweredOff) off")
            statCard(title: "Hosts", value: "\(data.hosts.count)", detail: nil)
            statCard(title: "Clusters", value: "\(data.clusters.count)", detail: nil)
            statCard(title: "Datastores", value: "\(data.datastores.count)", detail: String(format: "%.1f%% free", overallFreePercent))
        }
    }

    private func statCard(title: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.5))
            Text(value)
                .font(.system(size: 32, weight: .bold))
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var powerStateChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VM Power State").font(.system(size: 13, weight: .semibold))
            Chart {
                SectorMark(angle: .value("Count", poweredOn), innerRadius: .ratio(0.6)).foregroundStyle(.green)
                SectorMark(angle: .value("Count", poweredOff), innerRadius: .ratio(0.6)).foregroundStyle(.gray)
                if suspended > 0 {
                    SectorMark(angle: .value("Count", suspended), innerRadius: .ratio(0.6)).foregroundStyle(.orange)
                }
            }
            .frame(height: 160)
            HStack(spacing: 12) {
                legendDot(.green, "Powered On (\(poweredOn))")
                legendDot(.gray, "Powered Off (\(poweredOff))")
                if suspended > 0 { legendDot(.orange, "Suspended (\(suspended))") }
            }
            .font(.system(size: 11))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Capped at the 10 largest datastores by capacity — a report is a
    /// summary, not a full vDatastore export (that's the vDatastore tab's
    /// job); more than ~10 bars stops being readable at a glance anyway.
    private var datastoreChart: some View {
        let topDatastores = data.datastores.sorted { $0.capacityMiB > $1.capacityMiB }.prefix(10)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Datastore Free Space").font(.system(size: 13, weight: .semibold))
            Chart(Array(topDatastores)) { ds in
                BarMark(x: .value("Free %", ds.freePercent), y: .value("Datastore", ds.name))
                    .foregroundStyle(ds.freePercent < 10 ? Color.red : Color.blue)
            }
            .chartXScale(domain: 0...100)
            .frame(height: 160)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    private var healthSummary: some View {
        HStack(spacing: 24) {
            Text("vHealth").font(.system(size: 13, weight: .semibold))
            legendDot(.red, "\(redCount) red finding\(redCount == 1 ? "" : "s")")
            legendDot(.yellow, "\(yellowCount) yellow finding\(yellowCount == 1 ? "" : "s")")
            if redCount == 0 && yellowCount == 0 {
                legendDot(.green, "No open findings")
            }
        }
        .font(.system(size: 12))
    }

    private var footer: some View {
        Text("Generated by vLens")
            .font(.system(size: 10))
            .foregroundStyle(Color.black.opacity(0.4))
    }
}
