import Foundation
import ZIPFoundation

/// Whether a column should be written as a real numeric XLSX cell or as
/// text, declared by the column's owner (`CSVExportable.xlsxColumnTypes`)
/// rather than guessed from the string value at write time. Guessing from
/// the value ("does this parse as Int/Double?") silently turned a VM named
/// "00123" into the number 123 (losing the leading zero) and a two-part
/// version string like "8.0" into a number — both real data, not edge
/// cases, since neither looks unusual to a human reading the export.
public enum XLSXColumnType: Sendable {
    case text
    case number
}

/// Minimal XLSX writer — one sheet per export, reusing each model's
/// existing `CSVExportable` header/row data (an .xlsx is just a zip of a
/// handful of small XML parts; no need for a full spreadsheet object model
/// or a heavy dependency to produce one). Each column's declared
/// `XLSXColumnType` decides real numeric cell vs. inline string — no
/// shared-strings table, which keeps this simple at the row counts these
/// exports deal with.
public enum XLSXWriter {
    public static func data<T: CSVExportable>(for rows: [T], sheetName: String) throws -> Data {
        try data(header: T.csvHeader, columnTypes: T.xlsxColumnTypes, rows: rows.map(\.csvRow), sheetName: sheetName)
    }

    public static func data(header: [String], columnTypes: [XLSXColumnType], rows: [[String]], sheetName: String) throws -> Data {
        precondition(columnTypes.count == header.count, "xlsxColumnTypes must have exactly one entry per csvHeader column")
        let archive = try Archive(accessMode: .create)
        let safeSheetName = sanitize(sheetName: sheetName)

        try add(contentTypesXML, to: archive, at: "[Content_Types].xml")
        try add(rootRelsXML, to: archive, at: "_rels/.rels")
        try add(workbookXML(sheetName: safeSheetName), to: archive, at: "xl/workbook.xml")
        try add(workbookRelsXML, to: archive, at: "xl/_rels/workbook.xml.rels")
        try add(worksheetXML(header: header, columnTypes: columnTypes, rows: rows), to: archive, at: "xl/worksheets/sheet1.xml")

        guard let result = archive.data else {
            throw XLSXError.archiveProducedNoData
        }
        return result
    }

    private static func add(_ xml: String, to archive: Archive, at path: String) throws {
        let bytes = Data(xml.utf8)
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(bytes.count),
            compressionMethod: .deflate
        ) { position, size in
            bytes.subdata(in: Int(position)..<Int(position) + size)
        }
    }

    // MARK: - XML parts

    private static var contentTypesXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
        """
    }

    private static var rootRelsXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
    }

    private static func workbookXML(sheetName: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="\(escapeXML(sheetName))" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """
    }

    private static var workbookRelsXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """
    }

    private static func worksheetXML(header: [String], columnTypes: [XLSXColumnType], rows: [[String]]) -> String {
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        xml += #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>"#

        // The header row is always text — a column titled "1234" isn't a
        // number, and headers are always plain strings anyway.
        xml += row(index: 1, values: header, columnTypes: Array(repeating: .text, count: header.count))
        for (offset, values) in rows.enumerated() {
            xml += row(index: offset + 2, values: values, columnTypes: columnTypes)
        }

        xml += "</sheetData></worksheet>"
        return xml
    }

    private static func row(index: Int, values: [String], columnTypes: [XLSXColumnType]) -> String {
        var xml = "<row r=\"\(index)\">"
        for (col, value) in values.enumerated() {
            let ref = "\(columnLetter(col))\(index)"
            let type = col < columnTypes.count ? columnTypes[col] : .text
            if type == .number, let number = numericCellValue(value) {
                xml += "<c r=\"\(ref)\"><v>\(number)</v></c>"
            } else {
                xml += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escapeXML(value))</t></is></c>"
            }
        }
        xml += "</row>"
        return xml
    }

    // MARK: - helpers

    /// Guards against writing an invalid `<v>` for a column that's declared
    /// `.number` but whose value, for this particular row, is empty (an
    /// unset optional metric) or otherwise not actually parseable —
    /// degrades to a text cell rather than producing malformed XLSX.
    private static func numericCellValue(_ s: String) -> String? {
        guard !s.isEmpty, s != "-" else { return nil }
        guard Int(s) != nil || Double(s) != nil else { return nil }
        return s
    }

    private static func columnLetter(_ index: Int) -> String {
        var i = index
        var letters = ""
        repeat {
            letters = String(UnicodeScalar(UInt8(65 + i % 26))) + letters
            i = i / 26 - 1
        } while i >= 0
        return letters
    }

    private static func escapeXML(_ s: String) -> String {
        var result = s
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        return result
    }

    /// Excel sheet names: max 31 chars, no `[ ] : * ? / \`.
    private static func sanitize(sheetName: String) -> String {
        let disallowed = CharacterSet(charactersIn: "[]:*?/\\")
        let cleaned = sheetName.components(separatedBy: disallowed).joined()
        return String(cleaned.prefix(31))
    }
}

public enum XLSXError: Error, Sendable {
    case archiveProducedNoData
}
