import Testing
import Foundation
@testable import MIMORunning

/// 빌드업 판정 — 양 끝 km(몸 풀기·스퍼트)만으로 평탄한 러닝이 빌드업이 되던 결함(2026-09-28) 회귀 방지.
@Suite("빌드업 판정 · 양 끝 km 제외 · 단계 1.5% · 추세 4%", .korean)
struct BuildUpVerdictTests {

    private func splits(_ paces: String) -> [SplitData] {
        paces.split(separator: " ").enumerated().map { i, p in
            let parts = p.split(separator: "'").compactMap { Double($0) }
            return SplitData(id: i + 1, distanceM: 1000, duration: parts[0] * 60 + parts[1],
                             avgHeartRate: nil, avgCadence: nil, avgPower: nil,
                             avgGroundContactTime: nil, avgStrideLength: nil, avgVerticalOscillation: nil)
        }
    }

    @Test("몸 풀기 + 마지막 스퍼트, 가운데 평탄 → 빌드업 아님")
    func warmupAndKickIsNotBuildUp() {
        #expect(!WorkoutTypeClassifier.isBuildUp(splits: splits("6'45 6'25 6'20 6'22 6'18 6'21 6'19 6'20 6'17 6'05")))
    }

    @Test("첫 km만 느리고 이후 평탄 → 빌드업 아님")
    func slowFirstKmIsNotBuildUp() {
        #expect(!WorkoutTypeClassifier.isBuildUp(splits: splits("6'50 6'22 6'18 6'20 6'15 6'17 6'14 6'10")))
    }

    @Test("신호 대기 첫 km + 평탄 + 스퍼트 → 빌드업 아님")
    func trafficLightStartIsNotBuildUp() {
        #expect(!WorkoutTypeClassifier.isBuildUp(splits: splits("7'05 6'30 6'28 6'31 6'26 6'12")))
    }

    @Test("처음 3km 몸 풀고 이후 평탄(중간에 빠른 km 하나) → 빌드업 아님")
    func warmupThenSteadyIsNotBuildUp() {
        #expect(!WorkoutTypeClassifier.isBuildUp(splits: splits("6'54 6'33 6'19 6'09 6'16 5'53 6'01 6'12 6'12 6'08")))
    }

    @Test("고르게 올린 10km → 빌드업")
    func steadyProgressionIsBuildUp() {
        #expect(WorkoutTypeClassifier.isBuildUp(splits: splits("6'40 6'35 6'30 6'25 6'20 6'15 6'10 6'05 6'00 5'55")))
    }

    @Test("3단 빌드업(이지→중간→템포) → 빌드업")
    func threeStageIsBuildUp() {
        #expect(WorkoutTypeClassifier.isBuildUp(splits: splits("6'40 6'40 6'38 6'15 6'14 6'15 5'50 5'49 5'48")))
    }

    @Test("후반 3km만 올린 7km → 추세로 빌드업")
    func lateSurgeIsBuildUp() {
        #expect(WorkoutTypeClassifier.isBuildUp(splits: splits("6'40 6'38 6'41 6'39 6'20 6'05 5'50")))
    }

    @Test("실사용 22km 빌드업(6'41\"→5'58\") → 빌드업")
    func realLongBuildUp() {
        let two = "6'41 6'39 6'23 6'10 6'15 6'21 6'17 6'18 6'12 5'58 6'02".split(separator: " ")
        #expect(WorkoutTypeClassifier.isBuildUp(splits: splits(two.flatMap { [$0, $0] }.joined(separator: " "))))
    }
}
