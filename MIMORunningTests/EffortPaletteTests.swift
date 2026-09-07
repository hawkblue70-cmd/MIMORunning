import Testing
import SwiftUI
@testable import MIMORunning

@Suite("EffortPalette 10색 · 4구간")
struct EffortPaletteTests {

    private func close(_ a: EffortPalette.RGBA, _ b: EffortPalette.RGBA) -> Bool {
        abs(a.r - b.r) < 0.02 && abs(a.g - b.g) < 0.02 && abs(a.b - b.b) < 0.02
    }

    @Test func endpointsMatchHRZoneRamp() {
        #expect(close(EffortPalette.rgba(EffortPalette.color(for: 1)), EffortPalette.rgba(Theme.hrZoneColors[0])))
        #expect(close(EffortPalette.rgba(EffortPalette.color(for: 10)), EffortPalette.rgba(Theme.hrZoneColors[4])))
        #expect(EffortPalette.colors.count == 10)
    }

    @Test func clampsOutOfRange() {
        #expect(close(EffortPalette.rgba(EffortPalette.color(for: 0)), EffortPalette.rgba(EffortPalette.color(for: 1))))
        #expect(close(EffortPalette.rgba(EffortPalette.color(for: 99)), EffortPalette.rgba(EffortPalette.color(for: 10))))
    }

    @Test func bands() {
        #expect(EffortBand(value: 1) == .easy)
        #expect(EffortBand(value: 3) == .easy)
        #expect(EffortBand(value: 4) == .moderate)
        #expect(EffortBand(value: 6) == .moderate)
        #expect(EffortBand(value: 7) == .hard)
        #expect(EffortBand(value: 8) == .hard)
        #expect(EffortBand(value: 9) == .allOut)
        #expect(EffortBand(value: 10) == .allOut)
        #expect(EffortBand.easy.range == 1...3)
        #expect(EffortBand.allOut.range == 9...10)
    }
}
