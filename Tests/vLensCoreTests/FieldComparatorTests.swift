import Foundation
import Testing
@testable import vLensCore

private struct Row {
    let name: String
    let score: Int
    let note: String?
}

@Test func valueComparatorSortsAscendingAndDescending() {
    let rows = [Row(name: "b", score: 2, note: nil), Row(name: "a", score: 1, note: nil), Row(name: "c", score: 3, note: nil)]

    var ascending = FieldComparator<Row>.value("name", \.name)
    ascending.order = .forward
    #expect(rows.sorted(using: ascending).map(\.name) == ["a", "b", "c"])

    var descending = FieldComparator<Row>.value("name", \.name)
    descending.order = .reverse
    #expect(rows.sorted(using: descending).map(\.name) == ["c", "b", "a"])
}

/// The subtle invariant this whole type exists to encode: an optional
/// field's nils sort last no matter which direction the user picked —
/// only the non-nil values should flip. Easy to silently break by naively
/// reversing the whole ComparisonResult.
@Test func optionalComparatorKeepsNilsLastInBothDirections() {
    let rows = [
        Row(name: "a", score: 1, note: "x"),
        Row(name: "b", score: 2, note: nil),
        Row(name: "c", score: 3, note: "y")
    ]

    var ascending = FieldComparator<Row>.optional("note", \.note)
    ascending.order = .forward
    #expect(rows.sorted(using: ascending).map(\.name) == ["a", "c", "b"]) // x < y, nil last

    var descending = FieldComparator<Row>.optional("note", \.note)
    descending.order = .reverse
    #expect(rows.sorted(using: descending).map(\.name) == ["c", "a", "b"]) // y < x reversed, nil STILL last
}

@Test func comparatorEqualityIsByFieldAndOrderOnly() {
    let a = FieldComparator<Row>.value("name", \.name)
    var b = FieldComparator<Row>.value("name", \.name)
    #expect(a == b)

    b.order = .reverse
    #expect(a != b)

    let differentField = FieldComparator<Row>.value("score", \.score)
    #expect(a != differentField)
}
