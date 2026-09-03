import SwiftUI
import AppKit

/// Renders `ReportView` to a single-page PDF via `ImageRenderer`'s
/// closure-based `render(rasterizationScale:renderer:)` — the documented way
/// to draw SwiftUI content into an arbitrary `CGContext` rather than just an
/// image. One page sized to the view's natural (dynamic) height — this is a
/// one-pager by design, not a paginated document.
@MainActor
enum ReportRenderer {
    static func renderPDF(_ view: ReportView) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2 // retina-quality vector/text rendering in the PDF

        var pdfData: Data?
        renderer.render { size, drawContent in
            let pdfMutableData = NSMutableData()
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: pdfMutableData as CFMutableData),
                let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                return
            }
            context.beginPDFPage(nil)
            drawContent(context)
            context.endPDFPage()
            context.closePDF()
            pdfData = pdfMutableData as Data
        }
        return pdfData
    }
}
