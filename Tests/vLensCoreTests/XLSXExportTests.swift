import Foundation
import Testing
import ZIPFoundation
@testable import vLensCore

@Test func xlsxRoundTripsThroughRealZipArchive() throws {
    let vm = VirtualMachineInfo(
        name: "web-01", powerState: .poweredOn, template: false,
        guestOSFullName: "Ubuntu Linux (64-bit)", cpuCount: 4, memoryMiB: 8192,
        hostName: "esxi-01", clusterName: "prod-cluster", resourcePoolName: nil,
        primaryIPAddress: "10.0.0.5", vmwareToolsStatus: "toolsOk", vmUUID: "abc-123"
    )

    let xlsxData = try XLSXWriter.data(for: [vm], sheetName: "vInfo")
    #expect(!xlsxData.isEmpty)

    // A real xlsx is a real zip — read it back with the same library that wrote it.
    let archive = try Archive(data: xlsxData, accessMode: .read)
    let paths = archive.map(\.path)
    #expect(paths.contains("xl/worksheets/sheet1.xml"))
    #expect(paths.contains("xl/workbook.xml"))
    #expect(paths.contains("[Content_Types].xml"))

    guard let sheetEntry = archive["xl/worksheets/sheet1.xml"] else {
        Issue.record("sheet1.xml missing from archive")
        return
    }
    var extracted = Data()
    _ = try archive.extract(sheetEntry) { extracted.append($0) }
    let xml = String(data: extracted, encoding: .utf8) ?? ""

    #expect(xml.contains("web-01"))
    #expect(xml.contains(">4<")) // cpuCount written as a real number, not inline string
    #expect(xml.contains("prod-cluster"))
}

@Test func xlsxEscapesXMLSpecialCharacters() throws {
    let vm = VirtualMachineInfo(
        name: "web<01>&\"test\"", powerState: .poweredOn, template: false,
        guestOSFullName: nil, cpuCount: 1, memoryMiB: 1024,
        hostName: "esxi-01", clusterName: nil, resourcePoolName: nil,
        primaryIPAddress: nil, vmwareToolsStatus: nil, vmUUID: "u1"
    )

    let xlsxData = try XLSXWriter.data(for: [vm], sheetName: "vInfo")
    let archive = try Archive(data: xlsxData, accessMode: .read)
    guard let sheetEntry = archive["xl/worksheets/sheet1.xml"] else {
        Issue.record("sheet1.xml missing from archive")
        return
    }
    var extracted = Data()
    _ = try archive.extract(sheetEntry) { extracted.append($0) }
    let xml = String(data: extracted, encoding: .utf8) ?? ""

    #expect(xml.contains("web&lt;01&gt;&amp;&quot;test&quot;"))
    #expect(!xml.contains("web<01>")) // raw angle brackets would corrupt the XML
}

@Test func xlsxSanitizesLongSheetNames() throws {
    let longName = String(repeating: "x", count: 50)
    let xlsxData = try XLSXWriter.data(header: ["A"], rows: [["1"]], sheetName: longName)
    let archive = try Archive(data: xlsxData, accessMode: .read)
    guard let workbookEntry = archive["xl/workbook.xml"] else {
        Issue.record("workbook.xml missing from archive")
        return
    }
    var extracted = Data()
    _ = try archive.extract(workbookEntry) { extracted.append($0) }
    let xml = String(data: extracted, encoding: .utf8) ?? ""
    #expect(!xml.contains(longName)) // must have been truncated to Excel's 31-char limit
}
