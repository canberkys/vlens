import AppKit
import UniformTypeIdentifiers

@MainActor
enum ExportPanel {
    /// Standard macOS save flow — NSSavePanel, not a custom picker. Runs
    /// synchronously on the main thread, which is fine: it's a modal sheet
    /// the user is actively looking at.
    static func saveCSV(content: String, suggestedFilename: String) {
        save(data: Data(content.utf8), contentType: .commaSeparatedText, suggestedFilename: suggestedFilename)
    }

    static func saveXLSX(data: Data, suggestedFilename: String) {
        save(data: data, contentType: .xlsx, suggestedFilename: suggestedFilename)
    }

    static func savePDF(data: Data, suggestedFilename: String) {
        save(data: data, contentType: .pdf, suggestedFilename: suggestedFilename)
    }

    private static func save(data: Data, contentType: UTType, suggestedFilename: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

private extension UTType {
    /// Apple doesn't ship a built-in `.xlsx` constant in UniformTypeIdentifiers —
    /// this is the standard registered UTI for Office Open XML spreadsheets.
    static let xlsx = UTType(filenameExtension: "xlsx")
        ?? UTType(exportedAs: "org.openxmlformats.spreadsheetml.sheet")
}
