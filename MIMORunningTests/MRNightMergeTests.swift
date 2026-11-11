import Testing
import Foundation
@testable import MIMORunning

@Suite("밤 값 덧붙이기 — 처음 400일, 이후 60일", .korean)
struct MRNightMergeTests {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: day, hour: 6))! }

    @Test func keepsOldBeforeWindowAndReplacesInside() {
        let old = [(date: d(8, 1), value: 40.0), (date: d(9, 10), value: 41.0), (date: d(9, 11), value: 42.0), (date: d(10, 20), value: 43.0)]
        // 창 시작 9/10 — 첫날(9/10)은 반쪽일 수 있어 저장값 유지, 9/11부터 새 값
        let new = [(date: d(9, 10), value: 99.0), (date: d(9, 11), value: 52.0), (date: d(11, 1), value: 55.0)]
        let m = mrMergeNights(old: old, new: new, windowStart: cal.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 14))!,
                              calendar: cal)
        #expect(m.map(\.value) == [40, 41, 52, 55])
    }

    @Test func emptyOldGivesNew() {
        let new = [(date: d(9, 12), value: 50.0)]
        #expect(mrMergeNights(old: [], new: new, windowStart: d(9, 10), calendar: cal).map(\.value) == [50])
    }
}
