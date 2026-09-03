import Foundation

/// A named, closure-driven `SortComparator` so every tab table gets
/// click-to-sort — including columns backed by optional fields — without
/// juggling `KeyPathComparator<Root>` (which only handles non-optional
/// `Comparable` key paths). `field` backs `Equatable` conformance (SwiftUI
/// needs comparators to be equatable to detect header-click changes).
/// Lives in vLensCore rather than the app target — `SortComparator`/
/// `SortOrder`/`ComparisonResult` are plain Foundation types, no SwiftUI
/// dependency, so this is reusable (and testable) outside the UI layer.
public struct FieldComparator<Root>: SortComparator {
    public let field: String
    public var order: SortOrder = .forward
    private let comparison: (Root, Root, SortOrder) -> ComparisonResult

    public init(_ field: String, order: SortOrder = .forward, comparison: @escaping (Root, Root, SortOrder) -> ComparisonResult) {
        self.field = field
        self.order = order
        self.comparison = comparison
    }

    public static func == (lhs: FieldComparator<Root>, rhs: FieldComparator<Root>) -> Bool {
        lhs.field == rhs.field && lhs.order == rhs.order
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(field)
        hasher.combine(order)
    }

    public func compare(_ lhs: Root, _ rhs: Root) -> ComparisonResult {
        comparison(lhs, rhs, order)
    }
}

public extension FieldComparator {
    /// Non-optional `Comparable` field.
    static func value<V: Comparable>(_ field: String, _ keyPath: KeyPath<Root, V>) -> FieldComparator<Root> {
        FieldComparator(field) { lhs, rhs, order in
            let l = lhs[keyPath: keyPath], r = rhs[keyPath: keyPath]
            let base: ComparisonResult = l == r ? .orderedSame : (l < r ? .orderedAscending : .orderedDescending)
            return order == .forward ? base : base.flipped
        }
    }

    /// Optional `Comparable` field — nils always sort last, independent of
    /// ascending/descending (matches Finder/Mail column-sort convention).
    static func optional<V: Comparable>(_ field: String, _ keyPath: KeyPath<Root, V?>) -> FieldComparator<Root> {
        FieldComparator(field) { lhs, rhs, order in
            let l = lhs[keyPath: keyPath], r = rhs[keyPath: keyPath]
            switch (l, r) {
            case (nil, nil): return .orderedSame
            case (nil, _): return .orderedDescending
            case (_, nil): return .orderedAscending
            case let (lv?, rv?):
                let base: ComparisonResult = lv == rv ? .orderedSame : (lv < rv ? .orderedAscending : .orderedDescending)
                return order == .forward ? base : base.flipped
            }
        }
    }
}

private extension ComparisonResult {
    var flipped: ComparisonResult {
        switch self {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}
