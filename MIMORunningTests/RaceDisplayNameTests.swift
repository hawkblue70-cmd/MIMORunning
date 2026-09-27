import Testing
import Foundation
@testable import MIMORunning

/// 대회 이름·종목 표시 규칙. 문자열 검사는 `.korean` 트레이트로 언어를 태스크 로컬에 고정.
@Suite("대회 표시 이름·종목", .korean)
struct RaceDisplayNameTests {

    @Test func stripsLeadingYear() {
        #expect(RaceDisplayName.short("2026 춘천마라톤") == "춘천마라톤")
    }

    @Test func stripsEdition() {
        #expect(RaceDisplayName.short("제46회 조선일보 춘천마라톤") == "조선일보 춘천마라톤")
    }

    @Test func stripsEditionInsideParentheses() {
        #expect(RaceDisplayName.short("2026 서울마라톤 (제96회 동아마라톤)") == "서울마라톤 (동아마라톤)")
    }

    @Test func stripsTrailingYear() {
        #expect(RaceDisplayName.short("고구려 마라톤 2025") == "고구려 마라톤")
    }

    @Test func keepsPlainName() {
        #expect(RaceDisplayName.short("JTBC 마라톤") == "JTBC 마라톤")
    }

    @Test func stripsYearInMiddle() {
        #expect(RaceDisplayName.short("RUN SEOUL RUN 2025 (런서울런)") == "RUN SEOUL RUN (런서울런)")
    }

    @Test func stripsEditionAndYearTogether() {
        #expect(RaceDisplayName.short("제6회 2026 버킷런") == "버킷런")
    }

    @Test func stripsEditionInParenthesesWithoutJe() {
        #expect(RaceDisplayName.short("2026(20회) 선사마라톤 축제") == "선사마라톤 축제")
    }

    @Test func fallsBackToOriginalWhenEverythingStripped() {
        #expect(RaceDisplayName.short("2026 제5회") == "2026 제5회")
    }

    @Test func standardDistanceLabels() {
        #expect(RaceDisplayName.distanceLabel(km: 5.0) == "5K")
        #expect(RaceDisplayName.distanceLabel(km: 10.0) == "10K")
        #expect(RaceDisplayName.distanceLabel(km: 21.0975) == "하프")
        #expect(RaceDisplayName.distanceLabel(km: 42.195) == "풀")
    }

    @Test func nonStandardDistanceLabels() {
        #expect(RaceDisplayName.distanceLabel(km: 32.0) == "32K")
        #expect(RaceDisplayName.distanceLabel(km: 10.9) == "10.9K")
        #expect(RaceDisplayName.distanceLabel(km: 20.0) == "20K")
        #expect(RaceDisplayName.distanceLabel(km: 42.0) == "풀")
        #expect(RaceDisplayName.distanceLabel(km: 9.99) == "10K")
    }

    @Test(.english) func englishLabels() {
        #expect(RaceDisplayName.distanceLabel(km: 21.0975) == "Half")
        #expect(RaceDisplayName.distanceLabel(km: 42.195) == "Full")
    }
}
