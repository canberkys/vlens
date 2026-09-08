import SwiftUI

/// In-app feedback/bug-report, reached from the Help menu. Faz 5.1 of
/// `~/.claude/plans/swirling-painting-snail.md`. Submits silently — the app
/// POSTs to a small Cloudflare Worker (`feedback-relay/`) which holds the
/// one secret (a GitHub fine-grained PAT scoped to ONLY
/// `canberkys/vlens`'s Issues) and creates the GitHub issue server-side.
/// No credential ships inside this app binary; `Self.clientToken` below is
/// NOT a secret (see the Worker's own doc comment) — it only filters out
/// casual/accidental hits on the relay URL, not a determined attacker.
struct FeedbackView: View {
    @Bindable var viewModel: ConnectionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var kind: FeedbackKind = .bug
    @State private var title = ""
    @State private var description = ""
    @State private var submissionState: SubmissionState = .idle

    private enum FeedbackKind: String, CaseIterable, Identifiable {
        case bug = "Bug Report"
        case feature = "Feature Request"
        var id: String { rawValue }
        var apiValue: String { self == .bug ? "bug" : "feature" }
    }

    private enum SubmissionState: Equatable {
        case idle
        case sending
        case success(issueURL: String)
        case failure(message: String)
    }

    // Filled in once `feedback-relay/` is deployed — see its README.
    private static let relayURL = URL(string: "https://vlens-feedback-relay.canberkki.workers.dev")!
    private static let clientToken = "b294ea990fa2fae23b8430e7aaa4036b981bdb2a5db8ca706cf42361b817f172"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Send Feedback")
                .font(.title2.bold())

            Picker("Type", selection: $kind) {
                ForEach(FeedbackKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(isSending)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .disabled(isSending)

            VStack(alignment: .leading, spacing: 4) {
                Text("Description").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $description)
                    .frame(height: 140)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                    .disabled(isSending)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Included automatically — never your vCenter host, username, or password:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(diagnosticInfo)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            statusBanner

            Spacer(minLength: 0)

            HStack {
                Spacer()
                if case .success = submissionState {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSending {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Send Feedback")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.isEmpty || description.isEmpty || isSending)
                }
            }
        }
        .padding(24)
        .frame(width: 460, height: 520)
    }

    private var isSending: Bool {
        if case .sending = submissionState { return true }
        return false
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch submissionState {
        case .idle, .sending:
            EmptyView()
        case .success(let issueURL):
            Label("Thanks — filed as \(issueURL).", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var diagnosticInfo: String {
        var lines = ["macOS \(ProcessInfo.processInfo.operatingSystemVersionString)", "vLens \(AppVersion.shortVersion)"]
        if let vCenter = viewModel.vCenterInfo {
            lines.append("vCenter \(vCenter.version) (build \(vCenter.build))")
        }
        return lines.joined(separator: "\n")
    }

    private func submit() async {
        submissionState = .sending
        var request = URLRequest(url: Self.relayURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.clientToken, forHTTPHeaderField: "X-vLens-Client")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "type": kind.apiValue,
            "title": title,
            "description": description,
            "diagnostics": diagnosticInfo
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                submissionState = .failure(message: "No response from the feedback service.")
                return
            }
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if http.statusCode == 200, let issueURL = body?["issueUrl"] as? String {
                submissionState = .success(issueURL: issueURL)
            } else {
                let serverMessage = body?["error"] as? String
                submissionState = .failure(message: serverMessage ?? "Couldn't submit feedback (status \(http.statusCode)). Please try again later.")
            }
        } catch {
            submissionState = .failure(message: "Couldn't reach the feedback service: \(error.localizedDescription)")
        }
    }
}
