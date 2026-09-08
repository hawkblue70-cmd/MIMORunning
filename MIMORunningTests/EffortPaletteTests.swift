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

    @Test func colorsTableMatchesColorFor() {
        for i in 1...10 {
            #expect(close(EffortPalette.rgba(EffortPalette.colors[i - 1]), EffortPalette.rgba(EffortPalette.color(for: i))))
        }
    }

    @Test func interiorIsBetweenNeighbouringStops() {
        // 5 → t = 4/9*4 = 1.78 → stops[1]~stops[2] 사이 (f≈0.78)
        let c = EffortPalette.rgba(EffortPalette.color(for: 5))
        let a = EffortPalette.rgba(Theme.hrZoneColors[1])
        let b = EffortPalette.rgba(Theme.hrZoneColors[2])
        func between(_ x: CGFloat, _ p: CGFloat, _ q: CGFloat) -> Bool { x >= min(p, q) - 0.01 && x <= max(p, q) + 0.01 }
        #expect(between(c.r, a.r, b.r))
        #expect(between(c.g, a.g, b.g))
        #expect(between(c.b, a.b, b.b))
        // 정확한 f 검증: r = a.r + (b.r − a.r) × 0.777…
        let f: CGFloat = (4.0 / 9.0 * 4.0) - 1.0
        #expect(abs(c.r - (a.r + (b.r - a.r) * f)) < 0.02)
    }

    @Test func redChannelIsNonDecreasingBlueToRed() {
        let reds = (1...10).map { EffortPalette.rgba(EffortPalette.color(for: $0)).r }
        for i in 1..<reds.count { #expect(reds[i] >= reds[i - 1] - 0.02) }
    }

    @Test func bandClampsOutOfRange() {
        #expect(EffortBand(value: 0) == .easy)
        #expect(EffortBand(value: -7) == .easy)
        #expect(EffortBand(value: 42) == .allOut)
    }
}
