import Testing
@testable import MIMORunning

/// 심박 → 존 번호 — Zone 5 상한(추정 최대 심박)을 넘어도 Z5.
@Suite("심박 존 번호 판정")
struct HRZoneLookupTests {
    private let zones: [HRZoneData] = [
        HRZoneData(id: 1, name: "Z1", minBPM: 0,   maxBPM: 101, seconds: 0, fraction: 0),
        HRZoneData(id: 2, name: "Z2", minBPM: 102, maxBPM: 118, seconds: 0, fraction: 0),
        HRZoneData(id: 3, name: "Z3", minBPM: 119, maxBPM: 135, seconds: 0, fraction: 0),
        HRZoneData(id: 4, name: "Z4", minBPM: 136, maxBPM: 152, seconds: 0, fraction: 0),
        HRZoneData(id: 5, name: "Z5", minBPM: 153, maxBPM: 170, seconds: 0, fraction: 0),
    ]

    @Test func aboveEstimatedMaxIsZone5() {
        #expect(zones.zoneID(forBPM: 170) == 5)
        #expect(zones.zoneID(forBPM: 171) == 5)
        #expect(zones.zoneID(forBPM: 190) == 5)
    }

    @Test func insideBoundsUnchanged() {
        #expect(zones.zoneID(forBPM: 154) == 5)
        #expect(zones.zoneID(forBPM: 152) == 4)
        #expect(zones.zoneID(forBPM: 60) == 1)
        #expect([HRZoneData]().zoneID(forBPM: 150) == nil)
    }
}
