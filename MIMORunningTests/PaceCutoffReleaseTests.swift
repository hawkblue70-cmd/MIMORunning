import XCTest
@testable import MIMORunning

/// 페이스 컷오프가 "이상치 제외"를 넘어 **실제 훈련 패턴까지** 잘라내지 않는지 검증.
///
/// 배경: 가장 빠른 구간이 좁으면 하한(중앙값−1.5SD)이 바짝 붙어, 그보다 조금만 빨라도
/// 어느 밴드에도 못 들어간다. 밴드가 없으니 다음에도 또 밖으로 밀려나 자기 기준이 영영 안 생겼다.
/// 밖으로 밀려나는 러닝이 minSamples(5) 이상이면 컷오프를 푼다.
final class PaceCutoffReleaseTests: XCTestCase {

    private func makeActivity(date: Date, paceSecPerKm: Double) -> Activity {
        Activity(id: UUID(), type: .running, date: date,
                 duration: paceSecPerKm * 7.5, distance: 7500,
                 calories: 600, avgHeartRate: 150)
    }

    private func makeDetail(seed: Int) -> ActivityDetail {
        ActivityDetail(routeCoordinates: [], routeTimeOffsets: [], elevationGain: 40,
                       avgPower: 227, avgCadence: 166 + (seed % 13), splits: [], hrZones: [],
                       intervalSegments: [], workoutType: .general,
                       avgGroundContactTime: 235 + Double(seed % 21),
                       avgStrideLength: 0.85 + Double(seed % 15) * 0.01,
                       avgVerticalOscillation: 8.0 + Double(seed % 9) * 0.08,
                       vo2Max: 45.3, altitudeProfile: [], altitudeTimeProfile: [])
    }

    /// 이지런 20회(6'40~7'20) + 템포 8회(5'43~5'52) + 아주 빠른 러닝 `fastCount`회(5'25~5'32)
    @MainActor
    private func baseline(fastCount: Int) -> RunningFormBaseline {
        let cal = Calendar.current
        let today = Date()
        var inputs: [FormInput] = []
        var day = 1
        func add(_ pace: Double) {
            let d = cal.date(byAdding: .day, value: -day * 3, to: today)!
            if let fi = FormInput(activity: makeActivity(date: d, paceSecPerKm: pace),
                                  detail: makeDetail(seed: day)) { inputs.append(fi) }
            day += 1
        }
        // 실제 사용자 분포에 맞춘 비율 — 빠른 러닝이 전체의 약 25%(= tempoMin 경계)
        for i in 0..<39 { add(360 + Double((i * 13) % 81)) }  // 6'00~7'20 (이지·보통)
        for i in 0..<8  { add(343 + Double(i)) }              // 5'43~5'50 (템포)
        for i in 0..<fastCount { add(325 + Double(i % 8)) }   // 5'25~5'32 (아주 빠름)
        return FormBaselineEngine.compute(from: inputs)
    }

    /// 빠른 러닝이 5회 이상 쌓이면 하한이 풀려 자기 밴드를 갖는다
    @MainActor
    func testRepeatedFastRunsReleaseTheLowerCutoff() {
        let b = baseline(fastCount: 5)
        XCTAssertEqual(b.cutoffs.fastMin, 0, accuracy: 0.001,
                       "밖으로 밀려나는 러닝이 5회 이상이면 하한을 풀어야 한다")
        XCTAssertNotNil(b.cutoffs.band(of: 329),
                        "하한이 풀렸으면 5'29\" 러닝도 자기 구간(가장 빠른)에 속해야 한다")
        XCTAssertEqual(b.cutoffs.band(of: 329), .fast)
    }

    /// 1~2회뿐이면 원래 목적대로 이상치로 보고 잘라낸다
    @MainActor
    func testOneOffFastRunStaysExcluded() {
        let b = baseline(fastCount: 2)
        XCTAssertGreaterThan(b.cutoffs.fastMin, 0,
                             "2회뿐이면 이상치·오측정으로 보고 하한을 유지한다")
        XCTAssertNil(b.cutoffs.band(of: 300),
                     "하한보다 훨씬 빠른 기록은 여전히 비교 대상에서 제외된다")
    }

    /// 하한이 풀린 뒤에는 참고 밴드를 빌릴 필요가 없다 — 정식 판정으로 넘어간다
    @MainActor
    func testReleasedCutoffEndsReferenceBandMode() {
        let b = baseline(fastCount: 5)
        XCTAssertNil(RunFormCardView.referenceBand(in: b, paceSecPerKm: 329),
                     "자기 구간이 생겼으면 참고 띠를 빌리지 않는다")
        XCTAssertNotNil(b.bands[.fast], "가장 빠른 구간 밴드가 만들어져야 한다")
    }
}
