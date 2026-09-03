import SwiftUI
import AppKit

/// In-app feedback/bug-report, reached from the Help menu. Faz 5 of
/// `~/.claude/plans/swirling-painting-snail.md`. Two channels, both
/// zero-backend/zero-embedded-secret: a prefilled `mailto:` draft the user's
/// own mail client sends, and a prefilled GitHub "new issue" URL the user's
/// own browser/GitHub session sends — nothing leaves this machine
/// automatically in either case, no credential ships inside the app binary.
/// The GitHub channel needed `github.com/canberkys/vlens` (private) to
/// exist first — see the repo-creation note in the plan file.
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
    private static let githubRepo = "canberkys/vlens"

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
                Button("Open as GitHub Issue") { openAsGitHubIssue() }
                    .disabled(title.isEmpty)
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

    private func openAsGitHubIssue() {
        var components = URLComponents(string: "https://github.com/\(Self.githubRepo)/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: "\(description)\n\n---\n\(diagnosticInfo)"),
            URLQueryItem(name: "labels", value: kind == .bug ? "bug" : "enhancement")
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}
