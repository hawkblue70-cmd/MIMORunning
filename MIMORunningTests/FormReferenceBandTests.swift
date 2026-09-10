import XCTest
@testable import MIMORunning

/// 오늘 페이스가 개인 페이스 구간 밖일 때, 폼 카드가 "가장 가까운 구간"을 참고 띠로 빌려오는지 검증.
///
/// 배경: 평소 이지런만 하다가 훨씬 빠르게 달리면 `cutoffs.band(of:)`가 nil이 되어
/// 범위 바·km 차트 띠가 통째로 사라졌다(설명도 없이). 참고 밴드를 골라 점선으로 그린다.
final class FormReferenceBandTests: XCTestCase {

    private func makeActivity(date: Date, distanceM: Double, paceSecPerKm: Double) -> Activity {
        Activity(id: UUID(), type: .running, date: date,
                 duration: paceSecPerKm * distanceM / 1000,
                 distance: distanceM, calories: 600, avgHeartRate: 150)
    }

    private func makeDetail(cadence: Int, stride: Double, gct: Double, vo: Double) -> ActivityDetail {
        ActivityDetail(routeCoordinates: [], routeTimeOffsets: [], elevationGain: 40,
                       avgPower: 227, avgCadence: cadence, splits: [], hrZones: [],
                       intervalSegments: [], workoutType: .general,
                       avgGroundContactTime: gct, avgStrideLength: stride,
                       avgVerticalOscillation: vo, vo2Max: 45.3,
                       altitudeProfile: [], altitudeTimeProfile: [])
    }

    /// 이지런(6'40~7'20)만 30회 쌓인 기준선
    @MainActor
    private func easyOnlyBaseline() -> RunningFormBaseline {
        let cal = Calendar.current
        let today = Date()
        var inputs: [FormInput] = []
        for i in 1...30 {
            let d = cal.date(byAdding: .day, value: -i * 5, to: today)!
            let act = makeActivity(date: d, distanceM: 7500, paceSecPerKm: 400.0 + Double((i * 7) % 41))
            let det = makeDetail(cadence: 166 + ((i * 3) % 7),
                                 stride: 0.87 + Double((i * 5) % 9) * 0.01,
                                 gct: 240.0 + Double((i * 11) % 13),
                                 vo: 8.1 + Double((i * 4) % 7) * 0.06)
            if let fi = FormInput(activity: act, detail: det) { inputs.append(fi) }
        }
        return FormBaselineEngine.compute(from: inputs)
    }

    @MainActor
    func testFastRunOutsideBandsBorrowsFastestBand() {
        let baseline = easyOnlyBaseline()
        let fastPace = 329.0   // 5'29" — 평소 이지런보다 훨씬 빠름

        // 전제: 이 페이스는 어느 구간에도 속하지 않는다 → 판정용 밴드는 없다
        XCTAssertNil(baseline.cutoffs.band(of: fastPace),
                     "5'29\"가 구간 안이면 이 테스트의 전제가 깨진다")

        // 표시용 참고 밴드는 존재하고, 빠른 쪽에서 가장 가까운 밴드를 고른다
        let ref = RunFormCardView.referenceBand(in: baseline, paceSecPerKm: fastPace)
        XCTAssertNotNil(ref, "구간 밖이어도 참고 띠를 그릴 밴드를 찾아야 한다")
        XCTAssertEqual(ref?.band, .fast, "빠른 쪽으로 벗어났으면 가장 빠른 구간을 참고로 쓴다")
        XCTAssertTrue(RunFormCardView.isFaster(than: baseline, pace: fastPace))
    }

    /// 페이스가 330~520초로 넓게 퍼진 기준선 — 느린 쪽에도 상한(verySlowMax)이 생긴다.
    @MainActor
    private func wideSpreadBaseline() -> RunningFormBaseline {
        let cal = Calendar.current
        let today = Date()
        var inputs: [FormInput] = []
        for i in 1...40 {
            let d = cal.date(byAdding: .day, value: -i * 4, to: today)!
            let act = makeActivity(date: d, distanceM: 7500, paceSecPerKm: 330.0 + Double((i * 19) % 191))
            let det = makeDetail(cadence: 164 + ((i * 3) % 13),
                                 stride: 0.85 + Double((i * 5) % 15) * 0.01,
                                 gct: 235.0 + Double((i * 11) % 21),
                                 vo: 8.0 + Double((i * 4) % 9) * 0.08)
            if let fi = FormInput(activity: act, detail: det) { inputs.append(fi) }
        }
        return FormBaselineEngine.compute(from: inputs)
    }

    @MainActor
    func testSlowRunOutsideBandsBorrowsSlowestBand() {
        let baseline = wideSpreadBaseline()
        let slowPace = 1200.0   // 20'00" — 걷기에 가까움
        // 전제: 이 기준선은 느린 쪽 상한이 잡힌다 (표본이 흩어져 verySlow 구간이 3건 이상)
        XCTAssertLessThan(baseline.cutoffs.verySlowMax, slowPace,
                          "느린 쪽 상한이 없으면 '구간 밖'이 성립하지 않아 이 테스트가 무의미해진다")

        XCTAssertNil(baseline.cutoffs.band(of: slowPace))
        let ref = RunFormCardView.referenceBand(in: baseline, paceSecPerKm: slowPace)
        XCTAssertEqual(ref?.band, .verySlow, "느린 쪽으로 벗어났으면 가장 느린 구간을 참고로 쓴다")
        XCTAssertFalse(RunFormCardView.isFaster(than: baseline, pace: slowPace))
    }

    @MainActor
    func testPaceInsideBandsUsesNoReferenceBand() {
        let baseline = easyOnlyBaseline()
        let normalPace = 410.0   // 6'50" — 평소 구간 안

        XCTAssertNotNil(baseline.cutoffs.band(of: normalPace))
        XCTAssertNil(RunFormCardView.referenceBand(in: baseline, paceSecPerKm: normalPace),
                     "구간 안이면 자기 구간으로 판정한다 — 참고 밴드를 빌리면 안 된다")
    }

    @MainActor
    func testNoPaceUsesNoReferenceBand() {
        XCTAssertNil(RunFormCardView.referenceBand(in: easyOnlyBaseline(), paceSecPerKm: nil))
    }
}
