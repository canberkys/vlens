import Foundation
import Testing
@testable import vLensCore

@Test func decodesVirtualMachineInfoFromHelperJSON() throws {
    let json = """
    {"name":"web-01","powerState":"poweredOn","template":false,"guestOSFullName":"Ubuntu Linux (64-bit)","cpuCount":4,"memoryMiB":8192,"hostName":"esxi01.local","clusterName":"prod-cluster","resourcePoolName":null,"primaryIPAddress":"10.0.0.5","vmwareToolsStatus":"toolsOk","vmUUID":"abc-123"}
    """.data(using: .utf8)!

    let vm = try JSONDecoder().decode(VirtualMachineInfo.self, from: json)

    #expect(vm.name == "web-01")
    #expect(vm.powerState == .poweredOn)
    #expect(vm.resourcePoolName == nil)
    #expect(vm.cpuCount == 4)
}
