import SwiftUI

/// Custom About window — replaces SwiftUI's default (empty-looking in
/// development, since `swift run` has no real Info.plist to read from) app
/// info panel. See `AppVersion` for where the version numbers come from.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            AppIconImage.image
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text("vLens")
                .font(.title.bold())

            Text("Version \(AppVersion.shortVersion) (\(AppVersion.buildNumber))")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Native vCenter/ESXi inventory — inspired by RVTools, with features RVTools doesn't have.")
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
