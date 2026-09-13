import Testing
import Foundation
@testable import MIMORunning

/// 총평 5줄 규칙 — 축 순서·생략·톤·상태어. 문자열 검사라 직렬 실행.
@Suite("RunSummary 총평 줄", .serialized)
struct RunSummaryTests {

    private func lines(_ i: RunSummaryInput) -> [RunSummaryLine] {
        AppLanguage.shared.isEnglish = false
        return RunSummary.lines(i)
    }
    private func phase(_ late: FormPhase.Late) -> FormPhase.Result {
        FormPhase.Result(early: nil, mid: nil, late: late, earlyEndKm: 4, lateStartKm: 12, totalKm: 16)
    }

    @Test func emptyInputHasNoLines() {
        #expect(lines(RunSummaryInput()).isEmpty)
    }

    @Test func fullInputHasFiveLinesInOrder() {
        var i = RunSummaryInput()
        i.form = phase(.held)
        i.distKm = 16; i.typicalKm = 7.6
        i.workoutType = .distanceRun
        i.zoneFractions = [2: 0.10, 3: 0.20, 4: 0.62, 5: 0.08]
        i.weekOverWeek = 0.55; i.acuteChronic = .steady; i.streakDays = 4
        i.vo2 = 45.4; i.vo2AgeDecade = "50대"; i.vo2GenderLabel = "남성"
        let out = lines(i)
        #expect(out.map(\.axis) == ["러닝폼", "거리 적응", "심박", "훈련부하", "유산소"])
        #expect(out[0] == RunSummaryLine(axis: "러닝폼", state: "끝까지 유지", tone: .good))
        #expect(out[1] == RunSummaryLine(axis: "거리 적응", state: "평소 2.1배, 범위 안", tone: .good))
        #expect(out[2] == RunSummaryLine(axis: "심박", state: "계획대로 고강도", tone: .good))
        #expect(out[3] == RunSummaryLine(axis: "훈련부하", state: "이번 주 +55% · 4일 연속", tone: .neutral))
        #expect(out[4] == RunSummaryLine(axis: "유산소", state: "50대 남성 기준 높음", tone: .good))
    }

    // MARK: 러닝폼

    @Test func heavierFormIsNeutralWithShortState() {
        var i = RunSummaryInput(); i.form = phase(.heavier([.stride]))
        #expect(lines(i) == [RunSummaryLine(axis: "러닝폼", state: "마지막 4km 살짝 무거워짐", tone: .neutral)])
    }

    // MARK: 거리 적응

    @Test func distanceBelow130PercentIsOmitted() {
        var i = RunSummaryInput(); i.distKm = 9; i.typicalKm = 7.6
        #expect(lines(i).isEmpty)
    }

    @Test func distanceWithoutFormInfoOmitsRangeClaim() {
        var i = RunSummaryInput(); i.distKm = 16; i.typicalKm = 7.6
        #expect(lines(i) == [RunSummaryLine(axis: "거리 적응", state: "평소 2.1배", tone: .good)])
    }

    @Test func distanceWithHeavierFormIsNeutral() {
        var i = RunSummaryInput(); i.distKm = 16; i.typicalKm = 7.6; i.form = phase(.heavier([.stride]))
        #expect(lines(i).last == RunSummaryLine(axis: "거리 적응", state: "평소 2.1배", tone: .neutral))
    }

    // MARK: 심박

    @Test func zoneTwoMajorityIsJustRight() {
        var i = RunSummaryInput(); i.zoneFractions = [1: 0.1, 2: 0.7, 3: 0.2]
        #expect(lines(i) == [RunSummaryLine(axis: "심박", state: "딱 좋은 강도", tone: .good)])
    }

    @Test func easyIntentWithHighZonesIsFlagged() {
        var i = RunSummaryInput(); i.workoutType = .easy; i.zoneFractions = [2: 0.4, 3: 0.5, 4: 0.1]
        #expect(lines(i) == [RunSummaryLine(axis: "심박", state: "이지런 기준 높음 · Zone 3 이상 60%", tone: .neutral)])
    }

    @Test func plannedHighIntensityInZoneFourIsGood() {
        var i = RunSummaryInput(); i.workoutType = .tempo; i.zoneFractions = [3: 0.3, 4: 0.6, 5: 0.1]
        #expect(lines(i) == [RunSummaryLine(axis: "심박", state: "계획대로 고강도", tone: .good)])
    }

    @Test func generalRunInZoneFourIsNeutral() {
        var i = RunSummaryInput(); i.workoutType = .general; i.zoneFractions = [3: 0.3, 4: 0.6, 5: 0.1]
        #expect(lines(i) == [RunSummaryLine(axis: "심박", state: "고강도 구간이 많음 · Zone 3 이상 100%", tone: .neutral)])
    }

    @Test func distanceRunInHighZonesIsPlanned() {
        // 거리주는 레이스페이스 장거리 — 이지 의도도 아니고, Zone 4 우세면 계획대로
        var i = RunSummaryInput(); i.workoutType = .distanceRun; i.zoneFractions = [3: 0.2, 4: 0.7, 5: 0.1]
        #expect(lines(i) == [RunSummaryLine(axis: "심박", state: "계획대로 고강도", tone: .good)])
    }

    @Test func zoneTieBreaksToHigherZone() {
        var i = RunSummaryInput(); i.workoutType = .general; i.zoneFractions = [3: 0.45, 4: 0.45, 2: 0.10]
        #expect(lines(i) == [RunSummaryLine(axis: "심박", state: "고강도 구간이 많음 · Zone 3 이상 90%", tone: .neutral)])
    }

    @Test func zoneThreeDominantOnGeneralIsTempo() {
        var i = RunSummaryInput(); i.workoutType = .general; i.zoneFractions = [2: 0.3, 3: 0.5, 4: 0.2]
        #expect(lines(i) == [RunSummaryLine(axis: "심박", state: "템포 구간에 머묾", tone: .neutral)])
    }

    @Test func raceInHighZonesIsPlanned() {
        var i = RunSummaryInput(); i.workoutType = .race; i.zoneFractions = [4: 0.5, 5: 0.5]
        #expect(lines(i) == [RunSummaryLine(axis: "심박", state: "계획대로 고강도", tone: .good)])
    }

    @Test func englishEasyIntentLine() {
        AppLanguage.shared.isEnglish = true
        defer { AppLanguage.shared.isEnglish = false }
        var i = RunSummaryInput(); i.workoutType = .lsd; i.zoneFractions = [3: 0.6, 4: 0.4]
        let out = RunSummary.lines(i)
        #expect(out == [RunSummaryLine(axis: "Heart rate", state: "High for LSD · 100% in Zone 3+", tone: .neutral)])
    }

    @Test func zoneOneDominantIsRecovery() {
        var i = RunSummaryInput(); i.zoneFractions = [1: 0.6, 2: 0.4]
        #expect(lines(i) == [RunSummaryLine(axis: "심박", state: "가벼운 회복 강도", tone: .good)])
    }

    @Test func heartRateLineAppendsHeatNoteOnNeutralTone() {
        var i = RunSummaryInput(); i.workoutType = .general; i.zoneFractions = [3: 0.3, 4: 0.6, 5: 0.1]; i.heatDeltaBpm = 8
        #expect(lines(i) == [RunSummaryLine(axis: "심박", state: "고강도 구간이 많음 · Zone 3 이상 100% · 더위 +8bpm 감안", tone: .neutral)])
    }
    @Test func heartRateLineNoHeatNoteWhenSmallOrGood() {
        var i = RunSummaryInput(); i.workoutType = .general; i.zoneFractions = [3: 0.3, 4: 0.6, 5: 0.1]; i.heatDeltaBpm = 3
        #expect(lines(i).first?.state == "고강도 구간이 많음 · Zone 3 이상 100%")
        var g = RunSummaryInput(); g.zoneFractions = [2: 0.7, 3: 0.3]; g.heatDeltaBpm = 8
        #expect(lines(g).first?.state == "딱 좋은 강도")
    }

    // MARK: 훈련부하

    @Test func streakAloneShowsWithoutLoadData() {
        var i = RunSummaryInput(); i.streakDays = 5
        #expect(lines(i) == [RunSummaryLine(axis: "훈련부하", state: "5일 연속", tone: .good)])
    }

    @Test func loadOmittedWithoutDataOrStreak() {
        var i = RunSummaryInput(); i.streakDays = 2
        #expect(lines(i).isEmpty)
    }

    @Test func steadyLoadIsGood() {
        var i = RunSummaryInput(); i.weekOverWeek = 0.05; i.acuteChronic = .steady
        #expect(lines(i) == [RunSummaryLine(axis: "훈련부하", state: "4주 평균 수준", tone: .good)])
    }

    @Test func highRatioWithoutWeekOverWeekUsesFourWeekWording() {
        var i = RunSummaryInput(); i.acuteChronic = .high
        #expect(lines(i) == [RunSummaryLine(axis: "훈련부하", state: "4주 평균 대비 높음", tone: .neutral)])
    }

    @Test func highRatioWithNegativeWeekOverWeekUsesFourWeekWording() {
        var i = RunSummaryInput(); i.acuteChronic = .veryHigh; i.weekOverWeek = -0.17
        #expect(lines(i) == [RunSummaryLine(axis: "훈련부하", state: "4주 평균 대비 높음", tone: .neutral)])
    }

    @Test func lowLoadIsLighter() {
        var i = RunSummaryInput(); i.weekOverWeek = -0.4; i.acuteChronic = .low
        #expect(lines(i) == [RunSummaryLine(axis: "훈련부하", state: "평소보다 가볍게", tone: .good)])
    }

    @Test func bigDropWithoutRatioIsLighter() {
        var i = RunSummaryInput(); i.weekOverWeek = -0.4
        #expect(lines(i) == [RunSummaryLine(axis: "훈련부하", state: "평소보다 가볍게", tone: .good)])
    }

    @Test func streakBelowThreeNotAppended() {
        var i = RunSummaryInput(); i.weekOverWeek = 0.0; i.streakDays = 2
        #expect(lines(i).first?.state == "4주 평균 수준")
    }

    // MARK: 유산소

    @Test func vo2Levels() {
        AppLanguage.shared.isEnglish = false
        #expect(RunSummary.vo2Level(20).name == "낮음")
        #expect(RunSummary.vo2Level(30).name == "평균이하")
        #expect(RunSummary.vo2Level(35).name == "평균이상")
        #expect(RunSummary.vo2Level(45.4).name == "높음")
        #expect(RunSummary.vo2Level(60).index == 3)
    }

    @Test func vo2BelowAverageIsNeutral() {
        var i = RunSummaryInput(); i.vo2 = 30; i.vo2AgeDecade = "50대"; i.vo2GenderLabel = ""
        #expect(lines(i) == [RunSummaryLine(axis: "유산소", state: "50대 기준 평균이하", tone: .neutral)])
    }
}
