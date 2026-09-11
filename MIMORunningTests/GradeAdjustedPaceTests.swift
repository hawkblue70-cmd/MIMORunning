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
