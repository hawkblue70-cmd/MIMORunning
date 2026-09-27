import Testing
import Foundation
@testable import MIMORunning

/// 번들 대회 DB의 시리즈 칸 — 같은 대회를 해마다 묶는 키(tools/race_series.py가 채움).
@Suite("대회 시리즈 칸")
struct RaceSeriesCSVTests {

    private var races: [BundledRace] {
        let d = RaceDetector()
        d.loadRacesForTesting()
        return d.races
    }

    private func series(_ name: String) -> String? {
        races.first { $0.name == name }?.series
    }

    @Test func everyRaceHasSeries() {
        #expect(races.allSatisfy { !($0.series ?? "").isEmpty })
    }

    @Test func chuncheonMarathonAcrossYears() {
        let s = series("제45회 조선일보 춘천마라톤")
        #expect(s != nil)
        #expect(series("제46회 조선일보 춘천마라톤") == s)
        #expect(series("2026 춘천마라톤") == s)
        #expect(series("2026 춘천봄내마라톤") != s)
    }

    @Test func renamedRacesJoinedByOverride() {
        #expect(series("2025 JTBC 서울마라톤") == series("2026 JTBC 마라톤"))
        #expect(series("2025 서울마라톤 (제95회 동아마라톤)") == series("2027 서울마라톤"))
        #expect(series("2025 서울마라톤 (제95회 동아마라톤)") == series("2026 서울마라톤 (제96회 동아마라톤)"))
    }

    @Test func ruleJoinsSuffixAndSpacingDifferences() {
        #expect(series("제21회 밀양아리랑마라톤대회") == series("제22회 밀양아리랑마라톤"))
        #expect(series("고구려 마라톤 2025") == series("2026 고구려 마라톤"))
    }

    @Test func springAndAutumnIncheonStaySeparate() {
        #expect(series("2025 인천마라톤") == series("2026 인천마라톤 (상반기)"))
        #expect(series("2025 인천마라톤대회") != series("2025 인천마라톤"))
    }
}
