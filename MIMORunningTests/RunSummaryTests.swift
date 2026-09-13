import Testing
import Foundation
@testable import MIMORunning

/// 총평 5줄 규칙 — 축 순서·생략·톤·상태어·근거·다음. 문자열 검사라 직렬 실행.
@Suite("RunSummary 총평 줄", .serialized)
struct RunSummaryTests {

    private func lines(_ i: RunSummaryInput) -> [RunSummaryLine] {
        AppLanguage.shared.isEnglish = false
        return RunSummary.lines(i)
    }
    private func phase(_ late: FormPhase.Late) -> FormPhase.Result {
        .stub(late: late, earlyEnd: 4, lateStart: 12, total: 16)
    }

    /// axis/state/tone만 비교 — evidence/next는 전용 테스트에서 별도로 검사한다.
    private func bare(_ lines: [RunSummaryLine]) -> [RunSummaryLine] {
        lines.map { RunSummaryLine(axis: $0.axis, state: $0.state, tone: $0.tone) }
    }

    // MARK: 근거·다음 픽스처 — FormPhaseTests의 split()/band 픽스처와 같은 기본값(평소 범위 한가운데)

    private func stat(_ median: Double, sd: Double) -> FormStat {
        FormStat(median: median, sd: sd, count: 30, p10: nil, p90: nil)
    }

    /// 평소 범위(±1.2SD, 반올림): 케이던스 171~179 · 보폭 0.88~0.96 · 접지 245~265
    private var band: FormPhase.BandStats {
        FormPhase.BandStats(cadence: stat(175, sd: 3), stride: stat(0.92, sd: 0.03), groundContact: stat(255, sd: 8))
    }

    private func split(_ id: Int, sl: Double? = 0.92, gct: Double? = 255) -> SplitData {
        SplitData(id: id, distanceM: 1000, duration: 375,
                  avgHeartRate: 150, avgCadence: 175, avgPower: nil,
                  avgGroundContactTime: gct, avgStrideLength: sl, avgVerticalOscillation: 8.4)
    }

    private func classify(_ splits: [SplitData]) -> FormPhase.Result? {
        FormPhase.classify(splits: splits, bandFor: { _ in band })
    }

    /// 16km 러닝, 폼 전 구간 평소 범위(.held) — 후반은 splits 12~16(마지막 5km).
    private func heldForm16km() -> FormPhase.Result {
        classify((1...16).map { split($0) })!
    }

    /// 10km 러닝, 후반(splits 8~10, 마지막 3km) 보폭 아래·접지 위 → .heavier([.stride, .groundContact]).
    private func heavierForm10km() -> FormPhase.Result {
        let splits = (1...7).map { split($0) } + (8...10).map { split($0, sl: 0.85, gct: 272) }
        return classify(splits)!
    }

    private func todayInput() -> RunSummaryInput {
        var i = RunSummaryInput()
        i.form = heldForm16km()
        i.distKm = 16; i.typicalKm = 7.6
        i.distanceRank = 1; i.distanceSampleCount = 10
        i.workoutType = .distanceRun
        i.zoneFractions = [2: 0.10, 3: 0.20, 4: 0.62, 5: 0.08]
        i.avgHeartRate = 149; i.peakHeartRate = 157
        i.temperatureC = 25; i.heatDeltaBpm = 8
        i.sevenDayAU = 1783; i.previousSevenAU = 1149
        i.weekOverWeek = 0.55; i.acuteChronic = .steady; i.streakDays = 4
        i.vo2 = 45.4; i.vo2AgeDecade = "50대"; i.vo2GenderLabel = "남성"
        i.vo2EightWeeksAgo = 44.6
        return i
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
        let raw = lines(i)
        #expect(raw.map(\.axis) == ["러닝폼", "거리 적응", "심박", "훈련부하", "유산소"])
        let out = bare(raw)
        #expect(out[0] == RunSummaryLine(axis: "러닝폼", state: "끝까지 유지", tone: .good))
        #expect(out[1] == RunSummaryLine(axis: "거리 적응", state: "평소 2.1배, 범위 안", tone: .good))
        #expect(out[2] == RunSummaryLine(axis: "심박", state: "계획대로 고강도", tone: .good))
        #expect(out[3] == RunSummaryLine(axis: "훈련부하", state: "이번 주 +55% · 4일 연속", tone: .neutral))
        #expect(out[4] == RunSummaryLine(axis: "유산소", state: "50대 남성 기준 높음", tone: .good))
    }

    // MARK: 러닝폼

    @Test func heavierFormIsNeutralWithShortState() {
        var i = RunSummaryInput(); i.form = phase(.heavier([.stride]))
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "러닝폼", state: "마지막 4km 살짝 무거워짐", tone: .neutral)])
    }

    // MARK: 거리 적응

    @Test func distanceBelow130PercentIsOmitted() {
        var i = RunSummaryInput(); i.distKm = 9; i.typicalKm = 7.6
        #expect(lines(i).isEmpty)
    }

    @Test func distanceWithoutFormInfoOmitsRangeClaim() {
        var i = RunSummaryInput(); i.distKm = 16; i.typicalKm = 7.6
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "거리 적응", state: "평소 2.1배", tone: .good)])
    }

    @Test func distanceWithHeavierFormIsNeutral() {
        var i = RunSummaryInput(); i.distKm = 16; i.typicalKm = 7.6; i.form = phase(.heavier([.stride]))
        #expect(bare(lines(i)).last == RunSummaryLine(axis: "거리 적응", state: "평소 2.1배", tone: .neutral))
    }

    // MARK: 심박

    @Test func zoneTwoMajorityIsJustRight() {
        var i = RunSummaryInput(); i.zoneFractions = [1: 0.1, 2: 0.7, 3: 0.2]
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "심박", state: "딱 좋은 강도", tone: .good)])
    }

    @Test func easyIntentWithHighZonesIsFlagged() {
        var i = RunSummaryInput(); i.workoutType = .easy; i.zoneFractions = [2: 0.4, 3: 0.5, 4: 0.1]
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "심박", state: "이지런 기준 높음 · Zone 3 이상 60%", tone: .neutral)])
    }

    @Test func plannedHighIntensityInZoneFourIsGood() {
        var i = RunSummaryInput(); i.workoutType = .tempo; i.zoneFractions = [3: 0.3, 4: 0.6, 5: 0.1]
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "심박", state: "계획대로 고강도", tone: .good)])
    }

    @Test func generalRunInZoneFourIsNeutral() {
        var i = RunSummaryInput(); i.workoutType = .general; i.zoneFractions = [3: 0.3, 4: 0.6, 5: 0.1]
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "심박", state: "고강도 구간이 많음 · Zone 3 이상 100%", tone: .neutral)])
    }

    @Test func distanceRunInHighZonesIsPlanned() {
        // 거리주는 레이스페이스 장거리 — 이지 의도도 아니고, Zone 4 우세면 계획대로
        var i = RunSummaryInput(); i.workoutType = .distanceRun; i.zoneFractions = [3: 0.2, 4: 0.7, 5: 0.1]
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "심박", state: "계획대로 고강도", tone: .good)])
    }

    @Test func zoneTieBreaksToHigherZone() {
        var i = RunSummaryInput(); i.workoutType = .general; i.zoneFractions = [3: 0.45, 4: 0.45, 2: 0.10]
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "심박", state: "고강도 구간이 많음 · Zone 3 이상 90%", tone: .neutral)])
    }

    @Test func zoneThreeDominantOnGeneralIsTempo() {
        var i = RunSummaryInput(); i.workoutType = .general; i.zoneFractions = [2: 0.3, 3: 0.5, 4: 0.2]
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "심박", state: "템포 구간에 머묾", tone: .neutral)])
    }

    @Test func raceInHighZonesIsPlanned() {
        var i = RunSummaryInput(); i.workoutType = .race; i.zoneFractions = [4: 0.5, 5: 0.5]
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "심박", state: "계획대로 고강도", tone: .good)])
    }

    @Test func englishEasyIntentLine() {
        AppLanguage.shared.isEnglish = true
        defer { AppLanguage.shared.isEnglish = false }
        var i = RunSummaryInput(); i.workoutType = .lsd; i.zoneFractions = [3: 0.6, 4: 0.4]
        let out = bare(RunSummary.lines(i))
        #expect(out == [RunSummaryLine(axis: "Heart rate", state: "High for LSD · 100% in Zone 3+", tone: .neutral)])
    }

    @Test func zoneOneDominantIsRecovery() {
        var i = RunSummaryInput(); i.zoneFractions = [1: 0.6, 2: 0.4]
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "심박", state: "가벼운 회복 강도", tone: .good)])
    }

    // MARK: 훈련부하

    @Test func streakAloneShowsWithoutLoadData() {
        var i = RunSummaryInput(); i.streakDays = 5
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "훈련부하", state: "5일 연속", tone: .good)])
    }

    @Test func loadOmittedWithoutDataOrStreak() {
        var i = RunSummaryInput(); i.streakDays = 2
        #expect(lines(i).isEmpty)
    }

    @Test func steadyLoadIsGood() {
        var i = RunSummaryInput(); i.weekOverWeek = 0.05; i.acuteChronic = .steady
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "훈련부하", state: "4주 평균 수준", tone: .good)])
    }

    @Test func highRatioWithoutWeekOverWeekUsesFourWeekWording() {
        var i = RunSummaryInput(); i.acuteChronic = .high
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "훈련부하", state: "4주 평균 대비 높음", tone: .neutral)])
    }

    @Test func highRatioWithNegativeWeekOverWeekUsesFourWeekWording() {
        var i = RunSummaryInput(); i.acuteChronic = .veryHigh; i.weekOverWeek = -0.17
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "훈련부하", state: "4주 평균 대비 높음", tone: .neutral)])
    }

    @Test func lowLoadIsLighter() {
        var i = RunSummaryInput(); i.weekOverWeek = -0.4; i.acuteChronic = .low
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "훈련부하", state: "평소보다 가볍게", tone: .good)])
    }

    @Test func bigDropWithoutRatioIsLighter() {
        var i = RunSummaryInput(); i.weekOverWeek = -0.4
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "훈련부하", state: "평소보다 가볍게", tone: .good)])
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
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "유산소", state: "50대 기준 평균이하", tone: .neutral)])
    }

    // MARK: 근거·다음 (Task 3)

    @Test func evidenceAndNextForTodayRun() {
        let out = lines(todayInput())
        #expect(out[0].evidence == "케이던스 175 유지 · 마지막 5km 보폭 0.92 범위 안 · 접지 255 범위 안")
        #expect(out[0].next == nil)
        #expect(out[1].evidence == "평소 7.6km · 최근 10회 중 가장 긴 거리")
        #expect(out[1].next == "이 거리는 2~3주 유지한 뒤 늘리세요. 롱런은 한 번에 평소의 1.3배 안에서.")
        #expect(out[2].evidence == "Zone 4 62% · 평균 149 · 후반 157까지 · 25°C(더위 +8)")
        #expect(out[2].next == "장거리는 후반 심박이 자연히 올라요. 거리를 한 번에 크게 늘리지 마세요.")
        #expect(out[3].evidence == "7일 1,783 AU · 이전 7일 1,149 · 4일 연속")
        #expect(out[3].next == "다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋아요.")
        #expect(out[4].evidence == "VO2max 45.4 · 8주 전 대비 +0.8")
        #expect(out[4].next == nil)
    }

    @Test func easyIntentHighHRSuggestsEasyPace() {
        var i = todayInput(); i.workoutType = .easy; i.easyPace = MRHRPaceLookup(paceSec: 400, n: 12, hrLo: 125, hrHi: 135)
        #expect(lines(i)[2].next == "다음 이지런은 Zone 2 상단, 6'40\" 정도로 가 보세요.")
    }

    @Test func restedSuggestsQualitySession() {
        var i = todayInput(); i.weekOverWeek = 0.05; i.acuteChronic = .steady; i.loadSentence = nil; i.daysSinceHardRun = 3; i.streakDays = 0
        #expect(lines(i)[3].next == "충분히 회복됐어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.")
    }

    @Test func planRecoveryPhaseOverrides() {
        var i = todayInput(); i.planPhase = "회복"
        #expect(lines(i)[3].next == "플랜상 회복 주예요. 이지런 위주로 가세요.")
    }

    @Test func heavierFormSuggestsWatchingLateStride() {
        var i = todayInput(); i.form = heavierForm10km()
        #expect(lines(i)[0].next == "다음 롱런은 같은 거리에서 후반 보폭만 지켜보세요.")
        #expect(lines(i)[0].evidence == "케이던스 175 유지 · 마지막 3km 보폭 0.85 범위 아래 · 접지 272 범위 위")
    }
}
