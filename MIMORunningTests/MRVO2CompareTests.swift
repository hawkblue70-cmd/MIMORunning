import XCTest
@testable import MIMORunning

final class MRVO2CompareTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)
    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 8) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // Daniels 표(VDOT 50): 5K 19:57 · 하프 1:31:35 · 풀 3:10:49 — 공식 풀이는 표와 1분 안쪽
    func testTimeForVDOTMatchesDanielsTable() {
        XCTAssertEqual(mrTimeForVDOT(50, distanceM: MRDistance.d5)!, 19.95, accuracy: 0.1)
        XCTAssertEqual(mrTimeForVDOT(50, distanceM: MRDistance.dH)!, 91.6, accuracy: 0.5)
        XCTAssertEqual(mrTimeForVDOT(50, distanceM: MRDistance.dF)!, 190.8, accuracy: 1.0)
    }

    // vdot(d, t)의 역함수다
    func testTimeForVDOTInvertsVDOT() {
        let t = mrTimeForVDOT(42.3, distanceM: MRDistance.d10)!
        XCTAssertEqual(vdot(distanceM: MRDistance.d10, timeMin: t), 42.3, accuracy: 0.001)
    }

    func testTimeForVDOTRejectsNonsense() {
        XCTAssertNil(mrTimeForVDOT(0, distanceM: MRDistance.d5))
        XCTAssertNil(mrTimeForVDOT(45, distanceM: 0))
    }

    // 대회 당일 표본은 그 대회로 갱신됐을 수 있어 빼고, 60일보다 오래된 값도 쓰지 않는다
    func testVO2BeforeExcludesRaceDayAndStale() {
        let race = day(2026, 4, 6)
        let samples: [(date: Date, value: Double)] = [
            (day(2026, 1, 1), 40.0),     // 95일 전 — 너무 오래됨
            (day(2026, 3, 20), 44.0),    // 17일 전 — 채택
            (day(2026, 4, 6, 12), 47.0), // 대회 당일 — 제외
        ]
        let r = mrVO2Before(samples, raceDate: race, calendar: cal)
        XCTAssertEqual(r?.value, 44.0)
        XCTAssertEqual(r?.ageDays, 17)

        XCTAssertNil(mrVO2Before([(day(2026, 1, 1), 40.0)], raceDate: race, calendar: cal))
    }

    func testCompareRowsComputeBothErrors() {
        let race = day(2026, 4, 6)
        let bt = [MRBacktestRow(date: race, label: "하프", actualMin: 100,
                                predictedMin: 104, loMin: nil, hiMin: nil, priorCount: 5)]
        let rows = mrVO2Compare(backtest: bt, vo2Samples: [(day(2026, 3, 30), 45.0)], calendar: cal)
        XCTAssertEqual(rows.count, 1)
        let r = rows[0]
        XCTAssertEqual(r.appErrPct!, 4.0, accuracy: 0.001)
        XCTAssertEqual(r.vo2Min!, mrTimeForVDOT(45, distanceM: MRDistance.dH)!, accuracy: 0.001)
        XCTAssertEqual(r.vo2ErrPct!, (r.vo2Min! - 100) / 100 * 100, accuracy: 0.001)
        XCTAssertEqual(r.raceVDOT, vdot(distanceM: MRDistance.dH, timeMin: 100), accuracy: 0.001)
    }

    // 둘 다 있는 행만 같은 표본으로 요약한다 — 한쪽만 있는 행이 섞이면 공정한 비교가 아니다
    func testSummaryUsesOnlyPairedRows() {
        let rows = [
            MRVO2CompareRow(date: day(2026, 1, 1), label: "10K", actualMin: 50,
                            appMin: 51, vo2: 45, vo2AgeDays: 3, vo2Min: 45, raceVDOT: 40),
            MRVO2CompareRow(date: day(2026, 2, 1), label: "10K", actualMin: 50,
                            appMin: 49, vo2: 45, vo2AgeDays: 3, vo2Min: 47.5, raceVDOT: 40),
            MRVO2CompareRow(date: day(2026, 3, 1), label: "10K", actualMin: 50,
                            appMin: 60, vo2: nil, vo2AgeDays: nil, vo2Min: nil, raceVDOT: 40),
        ]
        let s = mrVO2CompareSummary(rows).first { $0.label == "10K" }!
        XCTAssertEqual(s.n, 2)
        XCTAssertEqual(s.appMAE, 2.0, accuracy: 0.001)    // |+2%|, |−2%|
        XCTAssertEqual(s.appBias, 0.0, accuracy: 0.001)
        XCTAssertEqual(s.vo2MAE, 7.5, accuracy: 0.001)    // |−10%|, |−5%|
        XCTAssertEqual(s.vo2Bias, -7.5, accuracy: 0.001)  // 음수 = 실제보다 빠르게 예측
    }
}
