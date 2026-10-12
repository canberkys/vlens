import Foundation
import Testing
@testable import vLensCore

@Test func decodesVirtualMachineInfoFromHelperJSON() throws {
    let json = """
    {"name":"web-01","powerState":"poweredOn","template":false,"guestOSFullName":"Ubuntu Linux (64-bit)","cpuCount":4,"memoryMiB":8192,"hostName":"esxi01.local","clusterName":"prod-cluster","resourcePoolName":null,"primaryIPAddress":"10.0.0.5","vmwareToolsStatus":"toolsOk","vmUUID":"abc-123","consolidationNeeded":false,"pvscsiControllerCount":1,"configStatus":"green","tags":["prod","team-a"],"customAttributes":["Owner: infra-team"]}
    """.data(using: .utf8)!

    let vm = try JSONDecoder().decode(VirtualMachineInfo.self, from: json)

    #expect(vm.name == "web-01")
    #expect(vm.powerState == .poweredOn)
    #expect(vm.resourcePoolName == nil)
    #expect(vm.cpuCount == 4)
    #expect(vm.tags == ["prod", "team-a"])
    #expect(vm.customAttributes == ["Owner: infra-team"])
}

/// A VM persisted by v1.5.0 (snapshot "Include full VM inventory") has none
/// of the later fields — it must still decode, or the whole snapshots.json
/// fails to load.
@Test func decodesVirtualMachineInfoSavedByOlderVersion() throws {
    let json = """
    {"name":"web-01","powerState":"poweredOff","template":false,"cpuCount":2,"memoryMiB":4096,"hostName":"esxi01.local","vmUUID":"abc-123","consolidationNeeded":true}
    """.data(using: .utf8)!

    let vm = try JSONDecoder().decode(VirtualMachineInfo.self, from: json)

    #expect(vm.consolidationNeeded)
    #expect(vm.configStatus == .gray)
    #expect(vm.tags.isEmpty)
    #expect(vm.customAttributes.isEmpty)
    #expect(vm.pvscsiControllerCount == 0)
}

/// Encode → decode must still round-trip every field now that decoding is
/// hand-written.
@Test func virtualMachineInfoRoundTrips() throws {
    let json = """
    {"name":"db","powerState":"suspended","template":true,"cpuCount":8,"memoryMiB":1024,"hostName":"h","vmUUID":"u","folderName":"f","consolidationNeeded":false,"pvscsiControllerCount":2,"configStatus":"red","tags":["a"],"customAttributes":["K: V"]}
    """.data(using: .utf8)!
    let vm = try JSONDecoder().decode(VirtualMachineInfo.self, from: json)
    let again = try JSONDecoder().decode(VirtualMachineInfo.self, from: JSONEncoder().encode(vm))
    #expect(again.folderName == "f")
    #expect(again.configStatus == .red)
    #expect(again.pvscsiControllerCount == 2)
    #expect(again.tags == ["a"])
    #expect(again.customAttributes == ["K: V"])
}
