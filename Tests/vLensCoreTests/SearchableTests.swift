import Foundation
import Testing
@testable import vLensCore

private func makeVM(name: String, host: String = "esxi-01", ip: String? = nil) -> VirtualMachineInfo {
    VirtualMachineInfo(
        name: name, powerState: .poweredOn, template: false, guestOSFullName: "Ubuntu Linux (64-bit)",
        cpuCount: 2, memoryMiB: 4096, hostName: host, clusterName: nil, resourcePoolName: nil,
        primaryIPAddress: ip, vmwareToolsStatus: nil, vmUUID: "u1"
    )
}

@Test func emptyQueryMatchesEverything() {
    let vm = makeVM(name: "web-01")
    #expect(vm.matches(""))
}

@Test func matchIsCaseInsensitive() {
    let vm = makeVM(name: "WEB-PROD-01")
    #expect(vm.matches("web-prod"))
    #expect(vm.matches("WEB-PROD"))
}

@Test func matchesAcrossComposedFieldsNotJustName() {
    let vm = makeVM(name: "db-01", host: "esxi-42.lab.local", ip: "10.0.0.7")
    #expect(vm.matches("esxi-42"))
    #expect(vm.matches("10.0.0.7"))
    #expect(vm.matches("Ubuntu"))
}

@Test func nonMatchingQueryReturnsFalse() {
    let vm = makeVM(name: "db-01")
    #expect(!vm.matches("nonexistent-string-xyz"))
}
