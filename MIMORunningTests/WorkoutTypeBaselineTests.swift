import XCTest
@testable import MIMORunning

/// 분류 기준선(페이스·거리) — 중앙값 · 기간 창 · 인터벌/대회/3km 미만 제외
final class WorkoutTypeBaselineTests: XCTestCase {

    private let cal = Calendar.current
    private var anchor: Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 8))! }

    /// daysAgo일 전, distanceKm, paceSecPerKm 로 러닝 생성. temp = 기온(°C), nil이면 기온 없음.
    private func run(daysAgo: Int, km: Double, pace: Double, temp: Double? = nil, id: UUID = UUID()) -> Activity {
        let d = cal.date(byAdding: .day, value: -daysAgo, to: anchor)!
        return Activity(id: id, type: .running, date: d, duration: pace * km,
                        distance: km * 1000, calories: nil, avgHeartRate: 140, temperatureC: temp)
    }

    /// 15°C 초과 1°C당 속도 1% 감소(bHot1 = −0.01)로 학습된 더위 모델. 25°C → 페이스 ×e^−0.1 ≈ ×0.905.
    private var hotModel: MRHeatModel {
        var m = MRHeatModel(); m.ok = true; m.bHot1 = -0.01; return m
    }

    private func flatSplits(count: Int, pace: Double) -> [SplitData] {
        (1...count).map { SplitData(id: $0, distanceM: 1000, duration: pace, avgHeartRate: 140,
                                    avgCadence: nil, avgPower: nil, avgGroundContactTime: nil,
                                    avgStrideLength: nil, avgVerticalOscillation: nil) }
    }

    private var today: Activity { run(daysAgo: 0, km: 10, pace: 390) }

    // MARK: - median

    func testMedian() {
        XCTAssertEqual(WorkoutTypeClassifier.median([3, 1, 2]), 2)
        XCTAssertEqual(WorkoutTypeClassifier.median([4, 1, 3, 2]), 2.5)
        XCTAssertEqual(WorkoutTypeClassifier.median([]), 0)
    }

    // MARK: - 더위 환산

    func testHeatModelNormalizesBaselineTo15C() {
        // 서늘한 날 400 × 4회 + 더운 날(25°C) 442 × 4회. 442 × 0.905 ≈ 400 → 환산 중앙값은 400 근처
        var runs = (1...4).map { run(daysAgo: $0 * 3, km: 8, pace: 400, temp: 15) }
        runs += (1...4).map { run(daysAgo: $0 * 3 + 1, km: 8, pace: 442, temp: 25) }
        let raw = WorkoutTypeClassifier.baselinePace(activity: today, recentRuns: runs, typeOf: nil)
        let ref = WorkoutTypeClassifier.baselinePace(activity: today, recentRuns: runs, typeOf: nil, heat: hotModel)
        XCTAssertEqual(raw.value!, 421, accuracy: 1)   // 원본은 두 무리 사이
        XCTAssertEqual(ref.value!, 400, accuracy: 1)   // 환산하면 더운 날이 서늘한 날과 같은 자리
    }

    func testHeatModelNotOkIsIdentity() {
        let runs = (1...5).map { run(daysAgo: $0 * 3, km: 8, pace: 442, temp: 30) }
        let off = MRHeatModel()   // ok = false
        XCTAssertEqual(WorkoutTypeClassifier.baselinePace(activity: today, recentRuns: runs, typeOf: nil, heat: off).value, 442)
        XCTAssertEqual(WorkoutTypeClassifier.refPace(runs[0], heat: off), 442)
        // 기온이 없는 러닝은 모델이 있어도 원본
        XCTAssertEqual(WorkoutTypeClassifier.refPace(run(daysAgo: 1, km: 8, pace: 442, temp: nil), heat: hotModel), 442)
    }

    func testHotDayLongRunIsNotMisreadAsEasyWithHeatModel() {
        // 4주 기준선 400(15°C, 8km 6회). 오늘 30°C 12km 530 페이스, 스플릿 균일.
        //  원본: 530 > 400×1.15 → 이지런(페이스 폴백)  /  환산: 530×e^−0.15 ≈ 456 → 이지·거리주·LSD 아님 → 롱런
        let hist = (1...6).map { run(daysAgo: $0 * 4, km: 8, pace: 400, temp: 15) }
        let hot = run(daysAgo: 0, km: 12, pace: 530, temp: 30)
        let splits = flatSplits(count: 12, pace: 530)
        XCTAssertEqual(WorkoutTypeClassifier.classify(activity: hot, history: hist, splits: splits), .easy)
        XCTAssertEqual(WorkoutTypeClassifier.classify(activity: hot, history: hist, splits: splits, heat: hotModel), .longRun)
    }

    // MARK: - baselinePace

    func testPaceBaselineIsMedianNotMean() {
        // 4주 안 6회: 400×5 + 대회급 300 1회 → 평균 383, 중앙값 400
        var runs = (1...5).map { run(daysAgo: $0 * 4, km: 8, pace: 400) }
        runs.append(run(daysAgo: 2, km: 8, pace: 300))
        let b = WorkoutTypeClassifier.baselinePace(activity: today, recentRuns: runs, typeOf: nil)
        XCTAssertEqual(b.value, 400)
        XCTAssertEqual(b.count, 6)
        XCTAssertEqual(b.window, "4주")
    }

    func testPaceBaselineExcludesIntervalRaceAndShortRuns() {
        let interval = run(daysAgo: 1, km: 8, pace: 300)
        let race     = run(daysAgo: 3, km: 10, pace: 310)
        let short    = run(daysAgo: 5, km: 2.5, pace: 500)
        let normal   = (1...5).map { run(daysAgo: 6 + $0 * 3, km: 8, pace: 400) }
        let types: [UUID: WorkoutType] = [interval.id: .interval, race.id: .race]
        let b = WorkoutTypeClassifier.baselinePace(activity: today,
                                                   recentRuns: [interval, race, short] + normal,
                                                   typeOf: { types[$0] })
        XCTAssertEqual(b.value, 400)
        XCTAssertEqual(b.count, 5)
    }

    func testPaceBaselineFallsBackTo8WeeksThenLast10() {
        // 4주 안 3회뿐 → 8주로 확장하면 6회 → 8주 중앙값
        let in4w = (1...3).map { run(daysAgo: $0 * 7, km: 8, pace: 380) }
        let in8w = (1...3).map { run(daysAgo: 28 + $0 * 7, km: 8, pace: 420) }
        let b = WorkoutTypeClassifier.baselinePace(activity: today, recentRuns: in4w + in8w, typeOf: nil)
        XCTAssertEqual(b.window, "8주")
        XCTAssertEqual(b.count, 6)
        XCTAssertEqual(b.value!, 400, accuracy: 1e-9)

        // 8주에도 5회 미만 → 최근 10회 콜드 스타트 (3회 이상이면 OK)
        let sparse = [run(daysAgo: 10, km: 8, pace: 400), run(daysAgo: 70, km: 8, pace: 410), run(daysAgo: 120, km: 8, pace: 390)]
        let c = WorkoutTypeClassifier.baselinePace(activity: today, recentRuns: sparse, typeOf: nil)
        XCTAssertEqual(c.window, "최근10회")
        XCTAssertEqual(c.value, 400)

        // 2회뿐 → nil
        let two = Array(sparse.prefix(2))
        XCTAssertNil(WorkoutTypeClassifier.baselinePace(activity: today, recentRuns: two, typeOf: nil).value)
    }

    // MARK: - baselineDistance

    func testDistanceBaselineIsMedianOf4Weeks() {
        // 7km×4 + 20km 롱런 1회 → 평균 9.6km, 중앙값 7km
        var runs = (1...4).map { run(daysAgo: $0 * 5, km: 7, pace: 400) }
        runs.append(run(daysAgo: 3, km: 20, pace: 420))
        runs.append(run(daysAgo: 40, km: 30, pace: 420))   // 4주 밖 — 무시
        let d = WorkoutTypeClassifier.baselineDistance(activity: today, recentRuns: runs)
        XCTAssertEqual(d, 7000)
    }

    func testDistanceBaselineNilBelow3Runs() {
        let runs = [run(daysAgo: 2, km: 7, pace: 400), run(daysAgo: 4, km: 7, pace: 400)]
        XCTAssertNil(WorkoutTypeClassifier.baselineDistance(activity: today, recentRuns: runs))
    }

    // MARK: - classify (기준선이 판정에 반영되는지)

    func testTenKmIsLongRunAgainstMedianDespitePriorLongRuns() {
        // 4주: 6km×5, 18km×2 → 평균 9.4km(×1.2=11.3 → 10km 탈락), 중앙값 6km(×1.2=7.2 → 10km 롱런)
        var hist = (1...5).map { run(daysAgo: $0 * 4, km: 6, pace: 400) }
        hist += [run(daysAgo: 6, km: 18, pace: 420), run(daysAgo: 13, km: 18, pace: 420)]
        // 페이스 6'30" = 기준 400×1.10=440 미만 → 거리주
        let t = WorkoutTypeClassifier.classify(activity: today, history: hist, splits: [])
        XCTAssertEqual(t, .distanceRun)
    }
}
