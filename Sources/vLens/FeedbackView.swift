import SwiftUI
import AppKit

/// In-app feedback/bug-report, reached from the Help menu. Faz 5 of
/// `~/.claude/plans/swirling-painting-snail.md`. Only the email channel is
/// built here — the GitHub Issue channel is deliberately withheld until the
/// project actually has a GitHub repo (it doesn't yet; that's a business
/// decision — public vs. private — not something to decide unilaterally).
///
/// No backend, no embedded secrets: this builds a prefilled `mailto:` URL
/// and hands it to the user's own mail client via `NSWorkspace` — they see
/// and send it themselves, nothing leaves this machine automatically.
struct FeedbackView: View {
    @Bindable var viewModel: ConnectionViewModel

    @State private var kind: FeedbackKind = .bug
    @State private var title = ""
    @State private var description = ""

    private enum FeedbackKind: String, CaseIterable, Identifiable {
        case bug = "Bug Report"
        case feature = "Feature Request"
        var id: String { rawValue }
    }

    /// Default recipient — the developer's own address, a reasonable
    /// default since a report only ever needs to reach them, not a third
    /// party. **Confirm or change this** before relying on it for real user
    /// feedback; see Faz 5 in the plan file.
    private static let recipientEmail = "kayit@canberkki.com"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Send Feedback")
                .font(.title2.bold())

            Picker("Type", selection: $kind) {
                ForEach(FeedbackKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Description").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $description)
                    .frame(height: 140)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Included automatically — never your vCenter host, username, or password:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(diagnosticInfo)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Send via Email") { sendViaEmail() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460, height: 500)
    }

    private var diagnosticInfo: String {
        var lines = ["macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        if let vCenter = viewModel.vCenterInfo {
            lines.append("vCenter \(vCenter.version) (build \(vCenter.build))")
        }
        return lines.joined(separator: "\n")
    }

    private func sendViaEmail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.recipientEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "[vLens \(kind.rawValue)] \(title)"),
            URLQueryItem(name: "body", value: "\(description)\n\n---\n\(diagnosticInfo)")
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}
