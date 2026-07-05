import Testing
@testable import SpudDataKit

struct InstanceSoftwareTests {
    @Test
    func mapsKnownNamesCaseInsensitively() {
        #expect(InstanceSoftware(softwareName: "lemmy") == .lemmy)
        #expect(InstanceSoftware(softwareName: "PieFed") == .piefed)
        #expect(InstanceSoftware(softwareName: "MBIN") == .mbin)
        #expect(InstanceSoftware(softwareName: "mastodon") == .mastodon)
    }

    @Test
    func preservesUnknownNameVerbatim() {
        #expect(InstanceSoftware(softwareName: "sublinks") == .other("sublinks"))
        #expect(InstanceSoftware(softwareName: "") == .other(""))
    }
}
