import Foundation
import Testing
@testable import vLensCore

@Test func csvWriterEscapesCommasQuotesAndNewlines() {
    let vm = VirtualMachineInfo(
        name: "web,01", powerState: .poweredOn, template: false,
        guestOSFullName: "Windows \"Server\" 2022", cpuCount: 2, memoryMiB: 4096,
        hostName: "esxi-01", clusterName: nil, resourcePoolName: nil,
        primaryIPAddress: nil, vmwareToolsStatus: nil, vmUUID: "u1"
    )

    let csv = CSVWriter.write([vm])
    let lines = csv.components(separatedBy: "\r\n")

    #expect(lines[0] == VirtualMachineInfo.csvHeader.joined(separator: ","))
    #expect(lines[1].hasPrefix("\"web,01\","))
    #expect(lines[1].contains("\"Windows \"\"Server\"\" 2022\""))
}

@Test func csvWriterLeavesPlainFieldsUnquoted() {
    let vm = VirtualMachineInfo(
        name: "web-01", powerState: .poweredOn, template: false,
        guestOSFullName: nil, cpuCount: 2, memoryMiB: 4096,
        hostName: "esxi-01", clusterName: nil, resourcePoolName: nil,
        primaryIPAddress: nil, vmwareToolsStatus: nil, vmUUID: "u1"
    )

    let csv = CSVWriter.write([vm])
    #expect(csv.contains("web-01,poweredOn,False"))
}
