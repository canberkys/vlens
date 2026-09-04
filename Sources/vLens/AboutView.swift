import SwiftUI

/// Custom About window — replaces SwiftUI's default (empty-looking in
/// development, since `swift run` has no real Info.plist to read from) app
/// info panel. See `AppVersion` for where the version numbers come from.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.16, green: 0.32, blue: 0.62), Color(red: 0.08, green: 0.16, blue: 0.36)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 96, height: 96)
                Image(systemName: "server.rack")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.white)
            }

            Text("vLens")
                .font(.title.bold())

            Text("Version \(AppVersion.shortVersion) (\(AppVersion.buildNumber))")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("A native macOS alternative to RVTools.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            Text("© 2026 Canberk Kılıçarslan")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 320)
    }
}

#Preview {
    AboutView()
}
