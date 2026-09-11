import XCTest
@testable import MIMORunning

/// GAP — 경사 조정 페이스.
final class GradeAdjustedPaceTests: XCTestCase {

    // MARK: 계수

    func testFlatGradeDoesNotAdjust() {
        XCTAssertEqual(GradeAdjustedPace.factor(grade: 0), 1.0, accuracy: 0.001)
        XCTAssertEqual(GradeAdjustedPace.energyCost(grade: 0), GradeAdjustedPace.flatCost, accuracy: 0.001)
    }

    func testUphillMakesGapFaster() {
        // 오르막은 같은 페이스라도 더 힘드니 평지 등가는 더 빠른 페이스여야 한다 (계수 < 1)
        let f5 = GradeAdjustedPace.factor(grade: 0.05)
        XCTAssertLessThan(f5, 1.0)
        // 5% 오르막 6'00(360초)이면 평지 등가는 4'30~5'20 사이 — 경험적으로 타당한 범위
        let gap = 360 * f5
        XCTAssertGreaterThan(gap, 270)
        XCTAssertLessThan(gap, 320)
    }

    func testSteeperUphillAdjustsMore() {
        XCTAssertLessThan(GradeAdjustedPace.factor(grade: 0.08),
                          GradeAdjustedPace.factor(grade: 0.03))
    }

    func testDownhillMakesGapSlowerButDamped() {
        let f = GradeAdjustedPace.factor(grade: -0.05)
        XCTAssertGreaterThan(f, 1.0, "내리막은 평지 등가가 느려야 한다")
        // 감쇠가 걸려 과하게 느려지지 않는다
        XCTAssertLessThan(f, 1.25, "대사 비용 그대로 쓰면 내리막 이득이 과대평가된다")
    }

    func testExtremeGradesAreClamped() {
        // 공식 유효 범위 밖은 잘라 쓴다 — 같은 값이 나와야 한다
        XCTAssertEqual(GradeAdjustedPace.factor(grade: 0.5),
                       GradeAdjustedPace.factor(grade: GradeAdjustedPace.maxGrade), accuracy: 0.0001)
        XCTAssertEqual(GradeAdjustedPace.factor(grade: -0.9),
                       GradeAdjustedPace.factor(grade: -GradeAdjustedPace.maxGrade), accuracy: 0.0001)
    }

    // MARK: 활동 단위

    private func splits(count: Int, paceSecPerKm: Double) -> [SplitData] {
        (1...count).map {
            SplitData(id: $0, distanceM: 1000, duration: paceSecPerKm,
                      avgHeartRate: 150, avgCadence: 178, avgPower: 227,
                      avgGroundContactTime: nil, avgStrideLength: nil, avgVerticalOscillation: nil)
        }
    }

    /// 총 거리 km, 고도가 start→end로 일정하게 변하는 프로파일
    private func profile(km: Double, from: Double, to: Double)
        -> [(distanceKm: Double, altitude: Double)] {
        let points = 60
        return (0...points).map { i in
            let t = Double(i) / Double(points)
            return (distanceKm: km * t, altitude: from + (to - from) * t)
        }
    }

    func testFlatCourseGapEqualsActualPace() throws {
        let gap = try XCTUnwrap(GradeAdjustedPace.compute(
            splits: splits(count: 5, paceSecPerKm: 360),
            altitudeProfile: profile(km: 5, from: 30, to: 30)))
        XCTAssertEqual(gap, 360, accuracy: 1, "평지면 보정이 없어야 한다")
    }

    func testUphillCourseGapIsFaster() throws {
        // 5km 동안 100m 상승 = 평균 2% 오르막
        let gap = try XCTUnwrap(GradeAdjustedPace.compute(
            splits: splits(count: 5, paceSecPerKm: 360),
            altitudeProfile: profile(km: 5, from: 0, to: 100)))
        XCTAssertLessThan(gap, 360, "오르막 코스는 평지 등가가 더 빨라야 한다")
        XCTAssertGreaterThan(gap, 300, "2% 오르막에서 60초 넘게 당겨지면 과보정")
    }

    func testDownhillCourseGapIsSlower() throws {
        let gap = try XCTUnwrap(GradeAdjustedPace.compute(
            splits: splits(count: 5, paceSecPerKm: 360),
            altitudeProfile: profile(km: 5, from: 100, to: 0)))
        XCTAssertGreaterThan(gap, 360, "내리막 코스는 평지 등가가 느려야 한다")
    }

    /// 롤링 코스 — 오르내림이 상쇄돼 순고도차가 0이어도 보정이 남아야 한다
    func testRollingCourseStillAdjusts() throws {
        var points: [(distanceKm: Double, altitude: Double)] = []
        for i in 0...100 {
            let km = 5.0 * Double(i) / 100
            points.append((distanceKm: km, altitude: 20 + 25 * sin(Double(i) / 100 * 6 * .pi)))
        }
        let gap = try XCTUnwrap(GradeAdjustedPace.compute(
            splits: splits(count: 5, paceSecPerKm: 360), altitudeProfile: points))
        XCTAssertNotEqual(gap, 360, accuracy: 0.5,
                          "순고도차가 0이어도 오르내림 비용은 남는다")
    }

    func testNoProfileReturnsNil() {
        XCTAssertNil(GradeAdjustedPace.compute(splits: splits(count: 5, paceSecPerKm: 360),
                                               altitudeProfile: []))
        XCTAssertNil(GradeAdjustedPace.compute(splits: [], altitudeProfile: profile(km: 5, from: 0, to: 50)))
    }

    // MARK: 경로 표본 기반 전체 계수 (백필용)

    /// 총 거리 km, 고도 from→to, 일정 페이스로 달린 경로 표본
    private func routeSamples(km: Double, from: Double, to: Double, paceSecPerKm: Double)
        -> [(distanceM: Double, altitude: Double, time: TimeInterval)] {
        let points = 120
        return (0...points).map { i in
            let t = Double(i) / Double(points)
            let distM = km * 1000 * t
            return (distanceM: distM,
                    altitude: from + (to - from) * t,
                    time: (distM / 1000) * paceSecPerKm)
        }
    }

    func testRouteFactorIsNeutralOnFlat() throws {
        let f = try XCTUnwrap(GradeAdjustedPace.overallFactor(
            routeSamples: routeSamples(km: 5, from: 20, to: 20, paceSecPerKm: 360)))
        XCTAssertEqual(f, 1.0, accuracy: 0.01)
    }

    func testRouteFactorUphillIsBelowOne() throws {
        let f = try XCTUnwrap(GradeAdjustedPace.overallFactor(
            routeSamples: routeSamples(km: 5, from: 0, to: 100, paceSecPerKm: 360)))
        XCTAssertLessThan(f, 1.0)
        XCTAssertGreaterThan(f, 0.80, "2% 오르막에서 20% 넘게 당겨지면 과보정")
    }

    func testRouteFactorDownhillIsAboveOne() throws {
        let f = try XCTUnwrap(GradeAdjustedPace.overallFactor(
            routeSamples: routeSamples(km: 5, from: 100, to: 0, paceSecPerKm: 360)))
        XCTAssertGreaterThan(f, 1.0)
    }

    /// 스플릿 기반 계산과 경로 기반 계수가 같은 코스에서 비슷한 답을 내야 한다
    func testRouteFactorAgreesWithSplitBasedGap() throws {
        let pace = 360.0
        let gapFromSplits = try XCTUnwrap(GradeAdjustedPace.compute(
            splits: splits(count: 5, paceSecPerKm: pace),
            altitudeProfile: profile(km: 5, from: 0, to: 100)))
        let factor = try XCTUnwrap(GradeAdjustedPace.overallFactor(
            routeSamples: routeSamples(km: 5, from: 0, to: 100, paceSecPerKm: pace)))
        XCTAssertEqual(pace * factor, gapFromSplits, accuracy: 6,
                       "두 계산 경로가 크게 갈리면 백필 표본과 화면 표시가 어긋난다")
    }

    func testRouteFactorNeedsEnoughSamples() {
        XCTAssertNil(GradeAdjustedPace.overallFactor(routeSamples: []))
        XCTAssertNil(GradeAdjustedPace.overallFactor(
            routeSamples: [(0, 10, 0), (50, 12, 30)]))
    }

    /// GPS 노이즈가 섞여도 평지는 평지로 읽혀야 한다 (평활화 검증)
    func testNoisyFlatProfileStaysNearActualPace() throws {
        var points: [(distanceKm: Double, altitude: Double)] = []
        for i in 0...200 {
            let km = 5.0 * Double(i) / 200
            let noise = (i % 2 == 0 ? 1.5 : -1.5)    // ±1.5m 톱니 노이즈
            points.append((distanceKm: km, altitude: 30 + noise))
        }
        let gap = try XCTUnwrap(GradeAdjustedPace.compute(
            splits: splits(count: 5, paceSecPerKm: 360), altitudeProfile: points))
        XCTAssertEqual(gap, 360, accuracy: 8, "노이즈가 경사로 읽히면 평지에서도 GAP이 크게 흔들린다")
    }
}

/// 페이스 구간 분류가 GAP 기준으로 도는지 — 언덕 러닝이 느린 구간으로 밀리지 않아야 한다.
final class GradeAdjustedBandTests: XCTestCase {

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

    /// 평지 러닝 위주 기준선에서, 언덕 때문에 느려진 러닝을 GAP으로 조회하면
    /// 실제 페이스로 조회할 때보다 빠른 구간에 들어간다.
    @MainActor
    func testHillyRunLandsInFasterBandWithGap() {
        let cal = Calendar.current
        let today = Date()
        var inputs: [FormInput] = []
        for i in 1...40 {
            let d = cal.date(byAdding: .day, value: -i * 4, to: today)!
            // 330~520초로 넓게 퍼진 평지 러닝
            let act = makeActivity(date: d, paceSecPerKm: 330 + Double((i * 19) % 191))
            if let fi = FormInput(activity: act, detail: makeDetail(seed: i)) { inputs.append(fi) }
        }
        let baseline = FormBaselineEngine.compute(from: inputs)

        // 언덕에서 6'40(400초)으로 달렸고, 평지 등가는 6'00(360초)
        let hilly = makeActivity(date: today, paceSecPerKm: 400)
        let rawBand = baseline.band(for: hilly)
        let gapBand = baseline.band(for: hilly, gradeAdjustedPace: 360)

        XCTAssertNotNil(rawBand)
        XCTAssertNotNil(gapBand)
        XCTAssertNotEqual(rawBand, gapBand,
                          "40초나 보정됐는데 같은 구간이면 GAP을 쓰는 의미가 없다")
    }

    /// GAP이 없으면(실내런·경로 없음) 실제 페이스로 조회한다 — 기존 동작 유지
    @MainActor
    func testNilGapFallsBackToActualPace() {
        let act = makeActivity(date: Date(), paceSecPerKm: 400)
        var inputs: [FormInput] = []
        let cal = Calendar.current
        for i in 1...40 {
            let d = cal.date(byAdding: .day, value: -i * 4, to: Date())!
            let a = makeActivity(date: d, paceSecPerKm: 330 + Double((i * 19) % 191))
            if let fi = FormInput(activity: a, detail: makeDetail(seed: i)) { inputs.append(fi) }
        }
        let baseline = FormBaselineEngine.compute(from: inputs)
        XCTAssertEqual(baseline.band(for: act, gradeAdjustedPace: nil), baseline.band(for: act))
    }

    /// FormInput의 유효 페이스 — GAP이 있으면 그것, 없으면 실제 페이스
    func testEffectivePacePrefersGap() {
        let act = Activity(id: UUID(), type: .running, date: Date(), duration: 3000,
                           distance: 7500, calories: 500, avgHeartRate: 150)
        let detail = ActivityDetail(routeCoordinates: [], routeTimeOffsets: [], elevationGain: nil,
                                    avgPower: nil, avgCadence: 175, splits: [], hrZones: [],
                                    intervalSegments: [], workoutType: .general,
                                    avgGroundContactTime: nil, avgStrideLength: nil,
                                    avgVerticalOscillation: nil, vo2Max: nil,
                                    altitudeProfile: [], altitudeTimeProfile: [])
        var input = FormInput(activity: act, detail: detail)
        XCTAssertNotNil(input)
        XCTAssertEqual(input?.effectivePaceSecPerKm, act.paceSecPerKm, "고도가 없으면 실제 페이스")
        input?.gradeAdjustedPaceSecPerKm = 333
        XCTAssertEqual(input?.effectivePaceSecPerKm, 333, "GAP이 있으면 그쪽을 쓴다")
    }
}
