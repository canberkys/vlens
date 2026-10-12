import AppKit

/// Double-click a column divider in any table header to size that column
/// to fit its content — the Finder/Excel gesture (requested on r/vmware).
///
/// SwiftUI's `Table` is an `NSTableView` underneath, but its delegate doesn't
/// implement `tableView(_:sizeToFitWidthOfColumn:)`, so AppKit's own
/// divider double-click does nothing. SwiftUI's hosted cells also report no
/// intrinsic size, so the content width is measured from what's actually
/// drawn instead: the column is briefly widened, each visible cell is
/// rendered offscreen, and the rightmost non-transparent pixel wins. That
/// keeps this one app-wide event monitor instead of duplicating every tab's
/// cell formatting just to measure it.
///
/// Relies on SwiftUI's Table being NSTableView-backed (true on macOS 14+).
/// If that ever changes, the hit test below simply finds no header view and
/// the gesture is a no-op — nothing else depends on it.
@MainActor
enum ColumnAutoFit {
    /// How close (in points) to a divider a double-click must land —
    /// roughly AppKit's own resize-cursor zone.
    private static let dividerTolerance: CGFloat = 4
    /// Right-side breathing room after the widest content.
    private static let contentPadding: CGFloat = 10
    /// Room for the header's sort indicator, which `cellSize` doesn't include.
    private static let headerPadding: CGFloat = 18
    /// Upper bound for a fitted column — one runaway cell (a long
    /// annotation) shouldn't produce a column wider than the window.
    private static let maxWidth: CGFloat = 800

    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if event.clickCount == 2, let target = dividerColumn(for: event) {
                // After the header's own (no-op) resize tracking for this
                // click has finished, not in the middle of it.
                DispatchQueue.main.async { sizeToFit(column: target.column, in: target.tableView) }
            }
            return event
        }
    }

    private static func dividerColumn(for event: NSEvent) -> (tableView: NSTableView, column: Int)? {
        // hitTest takes a point in the receiver's *superview* coordinates —
        // converting into the (flipped) SwiftUI content view itself lands
        // the hit on a table row instead of the header.
        guard let contentView = event.window?.contentView, let frameView = contentView.superview,
              let hit = contentView.hitTest(frameView.convert(event.locationInWindow, from: nil)) else { return nil }
        var view: NSView? = hit
        while let v = view, !(v is NSTableHeaderView) { view = v.superview }
        guard let header = view as? NSTableHeaderView, let tableView = header.tableView else { return nil }

        let point = header.convert(event.locationInWindow, from: nil)
        for column in 0..<tableView.numberOfColumns where !tableView.tableColumns[column].isHidden {
            let rect = header.headerRect(ofColumn: column)
            if abs(point.x - rect.maxX) <= dividerTolerance { return (tableView, column) }
        }
        return nil
    }

    static func sizeToFit(column: Int, in tableView: NSTableView) {
        guard column < tableView.numberOfColumns else { return }
        let tableColumn = tableView.tableColumns[column]
        // Widening one column can make AppKit shrink others under some
        // autoresizing styles — put every column back before applying the
        // real width.
        let originalWidths = tableView.tableColumns.map(\.width)

        tableColumn.width = maxWidth + contentPadding
        tableView.layoutSubtreeIfNeeded()

        var contentWidth: CGFloat = 0
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        for row in visibleRows.lowerBound..<visibleRows.upperBound {
            guard let cell = tableView.view(atColumn: column, row: row, makeIfNecessary: true) else { continue }
            cell.layoutSubtreeIfNeeded()
            contentWidth = max(contentWidth, inkWidth(of: cell))
        }

        for (index, width) in originalWidths.enumerated() {
            tableView.tableColumns[index].width = width
        }

        let headerWidth = tableColumn.headerCell.cellSize.width + headerPadding
        let fitted = max(contentWidth + contentPadding, headerWidth)
        tableColumn.width = min(max(fitted, tableColumn.minWidth), min(maxWidth, tableColumn.maxWidth))
    }

    /// Rightmost x (in the view's points) holding any non-transparent
    /// pixel, or 0 for an empty cell.
    static func inkWidth(of view: NSView) -> CGFloat {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return 0 }
        view.cacheDisplay(in: bounds, to: rep)
        return rightmostInk(in: rep) / (CGFloat(rep.pixelsWide) / bounds.width)
    }

    /// Pixel column just past the rightmost non-transparent pixel.
    static func rightmostInk(in rep: NSBitmapImageRep) -> CGFloat {
        guard let data = rep.bitmapData, rep.hasAlpha, rep.bitsPerPixel == 32 else { return 0 }
        let bytesPerRow = rep.bytesPerRow
        // Alpha position depends on the rep's format (ARGB vs RGBA).
        let alphaOffset = rep.bitmapFormat.contains(.alphaFirst) ? 0 : 3
        for x in stride(from: rep.pixelsWide - 1, through: 0, by: -1) {
            for y in 0..<rep.pixelsHigh where data[y * bytesPerRow + x * 4 + alphaOffset] > 16 {
                return CGFloat(x + 1)
            }
        }
        return 0
    }
}
