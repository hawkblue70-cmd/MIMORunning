import Testing
import Foundation
@testable import MIMORunning

/// 총평 5줄 규칙 — 축 순서·생략·톤·상태어·근거·다음. 문자열 검사는 `.korean` 트레이트로 언어를 태스크 로컬에 고정.
@Suite("RunSummary 총평 줄", .korean)
struct RunSummaryTests {

    private func lines(_ i: RunSummaryInput) -> [RunSummaryLine] {
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

    private func split(_ id: Int, cad: Int? = 175, sl: Double? = 0.92, gct: Double? = 255) -> SplitData {
        SplitData(id: id, distanceM: 1000, duration: 375,
                  avgHeartRate: 150, avgCadence: cad, avgPower: nil,
                  avgGroundContactTime: gct, avgStrideLength: sl, avgVerticalOscillation: 8.4)
    }

    private func classify(_ splits: [SplitData], easyFrame: Bool = false,
                          bandFor: @escaping (Double) -> FormPhase.BandStats? = { _ in nil }) -> FormPhase.Result? {
        FormPhase.classify(splits: splits, easyFrame: easyFrame, bandFor: { pace in bandFor(pace) ?? self.band })
    }

    /// 10km 러닝, 후반(splits 8~10) 케이던스만 평소 범위 아래 + 이지 프레임 → 무거워짐이 아니라 편한 날의 변화.
    private func easyFormCadenceOnly10km() -> FormPhase.Result {
        let splits = (1...7).map { split($0) } + (8...10).map { split($0, cad: 166) }
        return classify(splits, easyFrame: true)!
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

    /// 10km 러닝, 후반(splits 8~10) 케이던스만 평소 범위 아래 → .heavier([.cadence]) — 첫 지표가 케이던스.
    private func heavierFormCadence10km() -> FormPhase.Result {
        let splits = (1...7).map { split($0) } + (8...10).map { split($0, cad: 166) }
        return classify(splits)!
    }

    /// 16km 러닝, 기준선에 케이던스 기준이 없어(.unknown) 케이던스만 판정 불가 — 나머지는 평소 범위 안(.held).
    private func heldFormUnknownCadence16km() -> FormPhase.Result {
        let bandNoCadence = FormPhase.BandStats(cadence: nil, stride: stat(0.92, sd: 0.03), groundContact: stat(255, sd: 8))
        return classify((1...16).map { split($0) }, bandFor: { _ in bandNoCadence })!
    }

    private func todayInput() -> RunSummaryInput {
        var i = RunSummaryInput()
        i.form = heldForm16km()
        i.distKm = 16; i.typicalKm = 7.6
        i.distanceRank = 1; i.distanceSampleCount = 10
        i.workoutType = .distanceRun
        i.isLongDistanceContext = true
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
        // 최근 7일 +55%라도 상태어는 4주 평균 대비로만 — 증감은 근거 줄의 숫자. 4일 연속이라 톤은 중립.
        #expect(out[3] == RunSummaryLine(axis: "훈련부하", state: "4주 평균 수준 · 4일 연속", tone: .neutral))
        #expect(out[4] == RunSummaryLine(axis: "유산소", state: "50대 남성 기준 높음", tone: .good))
    }

    // MARK: 러닝폼

    @Test func heavierFormIsNeutralWithShortState() {
        var i = RunSummaryInput(); i.form = phase(.heavier([.stride]))
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "러닝폼", state: "마지막 4km 살짝 무거워짐", tone: .neutral)])
    }

    @Test func easySoftCadenceFormLineIsGoodWithoutNext() {
        var i = RunSummaryInput()
        i.form = easyFormCadenceOnly10km()
        i.workoutType = .easy
        let line = lines(i)[0]
        #expect(line.tone == .good)
        #expect(line.state == "편한 페이스 · 케이던스만 살짝 내려감")
        #expect(line.next == nil)
        #expect(line.evidence != nil)
    }

    @Test func shortRunNextSaysNextRun() {
        var i = RunSummaryInput()
        i.form = heavierForm10km()
        i.isLongDistanceContext = false
        #expect(lines(i)[0].next == "다음 러닝은 같은 거리에서 후반 보폭만 지켜보세요.")
    }

    @Test func distanceLineRunIsCalledLongRun() {
        // 장거리 문맥은 아니지만 거리 적응 줄이 뜨는 러닝(1.4배) → 호칭은 롱런
        var i = RunSummaryInput()
        i.form = heavierForm10km()
        i.isLongDistanceContext = false
        i.distKm = 10; i.typicalKm = 6.9
        #expect(lines(i)[0].next == "다음 롱런은 같은 거리에서 후반 보폭만 지켜보세요.")
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

    @Test func distanceRunInZoneThreeIsPlanned() {
        // Zone 3 우세여도 거리주는 계획된 고강도 유형 — "계획대로 템포 구간"
        var i = RunSummaryInput(); i.workoutType = .distanceRun; i.zoneFractions = [2: 0.2, 3: 0.66, 4: 0.14]
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "심박", state: "계획대로 템포 구간", tone: .good)])
    }

    @Test func intervalInZoneThreeIsPlannedHighIntensity() {
        // 인터벌은 평균 존이 회복 구간에 깎여 Zone 3 우세만으로도 고강도로 본다
        var i = RunSummaryInput(); i.workoutType = .interval; i.zoneFractions = [2: 0.2, 3: 0.41, 4: 0.3, 5: 0.09]
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

    @Test(.english) func englishEasyIntentLine() {
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
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "훈련부하", state: "5일 연속", tone: .neutral)])
    }

    @Test func loadOmittedWithoutDataOrStreak() {
        var i = RunSummaryInput(); i.streakDays = 2
        #expect(lines(i).isEmpty)
    }

    @Test func unratedTodayDoesNotClaimLighterLoad() {
        var i = RunSummaryInput(); i.weekOverWeek = -0.2; i.acuteChronic = .low; i.sevenDayAU = 1228; i.previousSevenAU = 1573
        i.todayEffortMissing = true
        let line = RunSummary.lines(i).first { $0.axis == "훈련부하" }
        #expect(line?.state == "오늘 강도 입력 전")
        #expect(line?.tone == .neutral)
        #expect(line?.evidence?.hasSuffix("오늘 러닝 미포함") == true)
        #expect(line?.next == "강도를 입력하면 오늘 러닝이 부하에 반영돼요.")
    }

    @Test func steadyLoadIsGood() {
        var i = RunSummaryInput(); i.weekOverWeek = 0.05; i.acuteChronic = .steady
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "훈련부하", state: "4주 평균 수준", tone: .good)])
    }

    @Test func highRatioWithoutWeekOverWeekUsesFourWeekWording() {
        var i = RunSummaryInput(); i.acuteChronic = .high
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "훈련부하", state: "4주 평균 대비 높음", tone: .neutral)])
    }

    @Test func veryHighRatioWithNegativeWeekOverWeekUsesFourWeekWording() {
        var i = RunSummaryInput(); i.acuteChronic = .veryHigh; i.weekOverWeek = -0.17
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "훈련부하", state: "4주 평균 대비 크게 높음", tone: .neutral)])
        #expect(lines(i)[0].evidence == "최근 7일 -17%")
    }

    @Test func lowLoadIsLighter() {
        var i = RunSummaryInput(); i.weekOverWeek = -0.4; i.acuteChronic = .low
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "훈련부하", state: "평소보다 가볍게", tone: .good)])
    }

    @Test func bigDropWithoutRatioIsNotJudged() {
        // 4주 비교가 없으면 증감 %만으로 가볍다/높다를 말하지 않는다 — 7일 합만, 그것도 없으면 "4주 비교 전"
        var i = RunSummaryInput(); i.weekOverWeek = -0.4
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "훈련부하", state: "4주 비교 전", tone: .good)])
        i.sevenDayAU = 1573
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "훈련부하", state: "7일 1,573 AU 기준", tone: .good)])
    }

    @Test func streakBelowThreeNotAppended() {
        var i = RunSummaryInput(); i.weekOverWeek = 0.0; i.acuteChronic = .steady; i.streakDays = 2
        #expect(lines(i).first?.state == "4주 평균 수준")
    }

    // MARK: 훈련부하 — 상태어는 4주 평균 대비로만, 증감은 근거 숫자 (창 경계 하루 차이로 결론이 뒤집히지 않게)

    @Test func bigWeekOverWeekWithSteadyRatioIsNotJumped() {
        // 실제 사례: 7일 1,691 · 이전 7일 1,046(+62%)이어도 4주 평균 대비 유지면 "이번 주 +62%"가 아니라 "4주 평균 수준"
        var i = RunSummaryInput(); i.weekOverWeek = 0.62; i.acuteChronic = .steady
        i.sevenDayAU = 1691; i.previousSevenAU = 1046
        let out = lines(i)
        #expect(bare(out) == [RunSummaryLine(axis: "훈련부하", state: "4주 평균 수준", tone: .good)])
        #expect(out[0].next != "다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋아요.")
        #expect(out[0].state.contains("이번 주") == false)
    }

    @Test func highRatioIsAboveFourWeekAvgWithRestAdvice() {
        var i = RunSummaryInput(); i.weekOverWeek = 0.10; i.acuteChronic = .high; i.sevenDayAU = 1691
        let out = lines(i)
        #expect(bare(out) == [RunSummaryLine(axis: "훈련부하", state: "4주 평균 대비 높음", tone: .neutral)])
        #expect(out[0].next == "다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋아요.")
    }

    @Test func evidenceAppendsSignedWeekOverWeek() {
        var i = RunSummaryInput(); i.weekOverWeek = 0.234; i.acuteChronic = .steady
        i.sevenDayAU = 1573; i.previousSevenAU = 1274
        #expect(lines(i)[0].evidence == "7일 1,573 AU · 이전 7일 1,274 · 최근 7일 +23%")
        inEnglish { #expect(RunSummary.lines(i)[0].evidence == "7-day 1,573 AU · previous 7 days 1,274 AU · Last 7 days +23%") }
    }

    @Test func steadyLoadWithLongStreakIsNeutral() {
        var i = RunSummaryInput(); i.weekOverWeek = 0.05; i.acuteChronic = .steady; i.streakDays = 4
        #expect(bare(lines(i)) == [RunSummaryLine(axis: "훈련부하", state: "4주 평균 수준 · 4일 연속", tone: .neutral)])
    }

    // MARK: 유산소

    @Test func vo2Levels() {
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
        #expect(out[0].evidence == "케이던스 175 유지 · 마지막 5km 보폭 0.92 범위 안 · 지면접촉 255 범위 안")
        #expect(out[0].next == nil)
        #expect(out[1].evidence == "평소 7.6km · 최근 10회 중 가장 긴 거리")
        #expect(out[1].next == "계획한 거리를 채운 러닝이에요. 다음 1~2일은 이지런이나 휴식으로 회복하세요.")
        #expect(out[2].evidence == "Zone 4 62% · 평균 149 · 최고 157 · 25°C(더위 +8)")
        // 거리 적응 줄이 이미 "장거리라 그렇다"를 말했으므로(거리 16km ≥ 평소 7.6km × 1.3) 심박 줄은 중복해서 말하지 않는다
        #expect(out[2].next == nil)
        // 연속일은 상태어에만 — 근거 줄에서는 빼서 같은 말이 두 번 보이지 않게 한다
        #expect(out[3].evidence == "7일 1,783 AU · 이전 7일 1,149 · 최근 7일 +55%")
        #expect(out[3].state == "4주 평균 수준 · 4일 연속")
        #expect(out[3].next == "다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋아요.")
        #expect(out[4].evidence == "VO2max 45.4 · 8주 전 대비 +0.8")
        #expect(out[4].next == nil)
    }

    @Test func easyIntentHighHRSuggestsEasyPace() {
        var i = todayInput(); i.workoutType = .easy; i.easyPace = MRHRPaceLookup(paceSec: 400, n: 12, hrLo: 125, hrHi: 135)
        #expect(lines(i)[2].next == "다음 이지런은 Zone 2 상단, 6'40\" 정도로 가 보세요.")
    }

    @Test func restedSuggestsQualitySession() {
        let i = restedInput()
        #expect(lines(i)[3].next == "충분히 회복됐어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.")
    }

    // MARK: 수면 HRV 결합

    private func hrv(_ state: MRHRVTrend.State, volatile: Bool = false) -> MRHRVTrend {
        MRHRVTrend(state: state, isVolatile: volatile, sevenDayMean: 37.4, baseline: 29.6, baselineSD: 3,
                   sevenDayCV: 0.05, baselineCV: 0.06, sevenDayNights: 7, baselineNights: 28)
    }

    /// 부하만으로는 "충분히 회복"인 입력 — `restedSuggestsQualitySession`과 HRV 결합 테스트가 공유.
    private func restedInput() -> RunSummaryInput {
        var i = todayInput(); i.weekOverWeek = 0.05; i.acuteChronic = .steady; i.loadSentence = nil
        i.daysSinceHardRun = 3; i.streakDays = 0; i.todayIsHard = false
        return i
    }

    @Test func hrvEvidenceMarksLastNightOutsideUsualRange() {
        // 기준선 29.6 · 문턱 ±15%(±4.4): 19(−36%)는 낮음, 28(−5%)은 범위 안, 35(+18%)는 높음
        var i = restedInput(); i.hrvTrend = hrv(.within); i.lastNightHRV = 19
        #expect(lines(i)[3].evidence?.hasSuffix("\nHRV 어젯밤 19(평소보다 낮음) · 7일 37 · 4주 30ms · 보통") == true)
        i.lastNightHRV = 28
        #expect(lines(i)[3].evidence?.hasSuffix("\nHRV 어젯밤 28 · 7일 37 · 4주 30ms · 보통") == true)
        i.lastNightHRV = 35
        #expect(lines(i)[3].evidence?.hasSuffix("\nHRV 어젯밤 35(평소보다 높음) · 7일 37 · 4주 30ms · 보통") == true)
    }

    @Test func hrvEvidenceAppendsSevenDayAndBaseline() {
        var i = restedInput(); i.hrvTrend = hrv(.within)
        #expect(lines(i)[3].evidence?.hasSuffix("\nHRV 7일 37ms · 4주 30ms · 보통") == true)
        inEnglish { #expect(lines(i)[3].evidence?.hasSuffix("\nHRV 7-day 37ms · 4-wk 30ms · normal") == true) }
    }

    @Test func hrvEvidenceGradeFollowsTrend() {
        // 상태어는 본인 기준선 대비 — 위·안정=좋음, 아래=낮음, 불안정=불안정(위여도 억제가 먼저)
        var i = restedInput()
        i.hrvTrend = hrv(.above)
        #expect(lines(i)[3].evidence?.hasSuffix(" · 좋음") == true)
        i.hrvTrend = hrv(.below)
        #expect(lines(i)[3].evidence?.hasSuffix(" · 낮음") == true)
        i.hrvTrend = hrv(.above, volatile: true)
        #expect(lines(i)[3].evidence?.hasSuffix(" · 불안정") == true)
        // 안정 상승(밴드 안이지만 기준선 위 + 7일 CV가 4주의 절반 미만)도 좋음
        i.hrvTrend = MRHRVTrend(state: .within, isVolatile: false, sevenDayMean: 27, baseline: 25, baselineSD: 5,
                                sevenDayCV: 0.07, baselineCV: 0.18, sevenDayNights: 7, baselineNights: 28)
        #expect(lines(i)[3].evidence?.hasSuffix("\nHRV 7일 27ms · 4주 25ms · 좋음") == true)
    }

    @Test func hrvStableRiseCountsAsReady() {
        // 실기기 로그 케이스: 7일 27ms(CV 7%) · 4주 25±5ms(CV 18%) → 밴드 안이지만 안정 상승 → 이지 블록 문장
        var i = restedInput(); i.hardRunsLast14 = 0; i.runsLast14 = 6
        i.hrvTrend = MRHRVTrend(state: .within, isVolatile: false, sevenDayMean: 27, baseline: 25, baselineSD: 5,
                                sevenDayCV: 0.07, baselineCV: 0.18, sevenDayNights: 7, baselineNights: 28)
        #expect(lines(i)[3].next == "2주 이지런으로 회복이 쌓였어요. HRV가 4주 기준선 위로 안정적이라 이번 주 강도 세션 넣기 좋아요.")
    }

    @Test func hrvWithinKeepsRestedSentence() {
        var i = restedInput(); i.hrvTrend = hrv(.within); i.hardRunsLast14 = 0; i.runsLast14 = 6
        #expect(lines(i)[3].next == "충분히 회복됐어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.")
    }

    @Test func hrvReadyAfterEasyBlockSuggestsQualityWeek() {
        var i = restedInput(); i.hrvTrend = hrv(.above); i.hardRunsLast14 = 1; i.runsLast14 = 6
        #expect(lines(i)[3].next == "2주 이지런으로 회복이 쌓였어요. HRV가 4주 기준선 위로 안정적이라 이번 주 강도 세션 넣기 좋아요.")
    }

    @Test func hrvReadyWithRecentHardRunsSaysAbsorbing() {
        var i = restedInput(); i.hrvTrend = hrv(.above); i.hardRunsLast14 = 2; i.runsLast14 = 6
        #expect(lines(i)[3].next == "충분히 회복됐어요. 고강도 뒤에도 HRV가 기준선 위라 부하를 잘 흡수하고 있어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.")
    }

    @Test func hrvReadyWithoutFourteenDayCountSaysAbsorbing() {
        // 추세는 있는데 14일 집계가 안 채워진 경우 — 이지 블록으로 보지 않는다
        var i = restedInput(); i.hrvTrend = hrv(.above); i.hardRunsLast14 = nil
        #expect(lines(i)[3].next?.hasPrefix("충분히 회복됐어요. 고강도 뒤에도") == true)
    }

    @Test func hrvEasyBlockNeedsFourRuns() {
        // 러닝 3회면 이지 블록이 아니다 → 흡수 문장
        var i = restedInput(); i.hrvTrend = hrv(.above); i.hardRunsLast14 = 0; i.runsLast14 = 3
        #expect(lines(i)[3].next?.hasPrefix("충분히 회복됐어요. 고강도 뒤에도") == true)
    }

    @Test func hrvBelowSuppressesRested() {
        var i = restedInput(); i.hrvTrend = hrv(.below); i.hardRunsLast14 = 0; i.runsLast14 = 6
        #expect(lines(i)[3].next == "부하는 내려왔지만 HRV가 기준선 아래예요. 수면이나 생활 피로 쪽일 수 있으니 하루 더 편하게 가세요.")
    }

    @Test func hrvVolatileSuppressesRestedEvenWhenAbove() {
        var i = restedInput(); i.hrvTrend = hrv(.above, volatile: true); i.hardRunsLast14 = 0; i.runsLast14 = 6
        #expect(lines(i)[3].next == "부하는 내려왔지만 HRV가 기준선 아래예요. 수면이나 생활 피로 쪽일 수 있으니 하루 더 편하게 가세요.")
    }

    @Test func hrvSuppressedAppendsToJumpSentence() {
        var i = todayInput(); i.acuteChronic = .high; i.loadSentence = .high; i.streakDays = 0; i.todayIsHard = false
        i.hrvTrend = hrv(.below)
        #expect(lines(i)[3].next == "다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋아요. HRV도 기준선 아래로 흔들리고 있어요.")
    }

    @Test func hrvAboveDoesNotTouchJumpSentence() {
        var i = todayInput(); i.acuteChronic = .high; i.loadSentence = .high; i.streakDays = 0; i.todayIsHard = false
        i.hrvTrend = hrv(.above)
        #expect(lines(i)[3].next == "다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋아요.")
    }

    @Test func hrvNilChangesNothing() {
        var i = restedInput(); i.hrvTrend = nil; i.hardRunsLast14 = 0; i.runsLast14 = 6
        #expect(lines(i)[3].next == "충분히 회복됐어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.")
        #expect(lines(i)[3].evidence?.contains("HRV") == false)
    }

    @Test func hardDayNextIsEasyTomorrow() {
        // 급증/단조/4일+연속이 아닌 날 — 오늘 강도를 냈으면 내일은 이지런이나 휴식
        var i = todayInput()
        i.weekOverWeek = 0.05; i.acuteChronic = .steady; i.loadSentence = nil; i.streakDays = 2
        i.todayIsHard = true
        #expect(lines(i)[3].next == "오늘 강도를 냈으니 내일은 이지런이나 휴식이 좋아요.")
    }

    @Test func loadSpikeBeatsHardDay() {
        // 4주 평균 대비 높음이면 오늘 강도를 냈어도 급증 경고가 우선한다 (연속일 규칙과 겹치지 않게 streak 2)
        var i = todayInput(); i.todayIsHard = true; i.acuteChronic = .high; i.streakDays = 2
        #expect(lines(i)[3].next == "다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋아요.")
    }

    @Test func steadyAfterHighYesterdaySaysComingDown() {
        // 어제 4주 평균 대비 높음 → 오늘 유지(8일 전 고강도가 창에서 빠진 것뿐)면 "충분히 회복"이 아니라 "내려오는 중"
        var i = todayInput(); i.weekOverWeek = 0.23; i.acuteChronic = .steady; i.acuteChronicYesterday = .high
        i.loadSentence = nil; i.daysSinceHardRun = 2; i.streakDays = 0; i.todayIsHard = false
        #expect(lines(i)[3].next == "부하가 내려오는 중이에요. 하루 더 편하게 가면 좋아요.")
        i.acuteChronicYesterday = .veryHigh; i.weekOverWeek = 0.05; i.daysSinceHardRun = 3
        #expect(lines(i)[3].next == "부하가 내려오는 중이에요. 하루 더 편하게 가면 좋아요.")
    }

    @Test func steadyWithRisingWeekIsNotRested() {
        // 유지라도 최근 7일이 +23%면(15% 이상) 아직 회복 국면이 아니다 — "충분히 회복" 대신 리듬 유지 + 고강도 간격
        var i = todayInput(); i.weekOverWeek = 0.23; i.acuteChronic = .steady; i.acuteChronicYesterday = .steady
        i.loadSentence = nil; i.daysSinceHardRun = 3; i.streakDays = 0; i.todayIsHard = false
        #expect(lines(i)[3].next == "지금 리듬을 유지하면 좋아요. 직전 7일보다 부하가 늘었으니 고강도 사이에는 쉬운 날 하루를 두세요.")
        // HRV가 위·안정이면 그 사실을 먼저 말하고 부하만 챙기라고 한다
        i.hrvTrend = MRHRVTrend(state: .above, isVolatile: false, sevenDayMean: 37, baseline: 30, baselineSD: 3,
                                sevenDayCV: 0.05, baselineCV: 0.06, sevenDayNights: 7, baselineNights: 28)
        #expect(lines(i)[3].next == "지금 리듬을 유지하면 좋아요. HRV는 좋고 직전 7일보다 부하가 늘었으니, 고강도 사이에는 쉬운 날 하루를 두세요.")
        // 범위 안이면 HRV를 말하지 않는다
        i.hrvTrend = MRHRVTrend(state: .within, isVolatile: false, sevenDayMean: 31, baseline: 30, baselineSD: 3,
                                sevenDayCV: 0.06, baselineCV: 0.06, sevenDayNights: 7, baselineNights: 28)
        #expect(lines(i)[3].next == "지금 리듬을 유지하면 좋아요. 직전 7일보다 부하가 늘었으니 고강도 사이에는 쉬운 날 하루를 두세요.")
    }

    @Test func steadyRecentHardRunKeepsRhythm() {
        // 유지 · 최근 7일 +5% · 마지막 고강도 1일 전 → 회복 판정은 아니지만 다음 줄은 비우지 않는다
        var i = todayInput(); i.weekOverWeek = 0.05; i.acuteChronic = .steady; i.acuteChronicYesterday = .steady
        i.loadSentence = nil; i.daysSinceHardRun = 1; i.streakDays = 0; i.todayIsHard = false
        #expect(lines(i)[3].next == "지금 리듬을 유지하면 좋아요.")
    }

    @Test func steadyFallbackDoesNotOverrideComingDown() {
        // 어제 높음 → 오늘 유지: "내려오는 중"이 유지 폴백보다 우선
        var i = todayInput(); i.weekOverWeek = 0.23; i.acuteChronic = .steady; i.acuteChronicYesterday = .high
        i.loadSentence = nil; i.daysSinceHardRun = 3; i.streakDays = 0; i.todayIsHard = false
        #expect(lines(i)[3].next == "부하가 내려오는 중이에요. 하루 더 편하게 가면 좋아요.")
    }

    @Test func steadyCalmWeekAfterSteadyYesterdayIsRested() {
        var i = todayInput(); i.weekOverWeek = 0.10; i.acuteChronic = .steady; i.acuteChronicYesterday = .steady
        i.loadSentence = nil; i.daysSinceHardRun = 3; i.streakDays = 0; i.todayIsHard = false
        #expect(lines(i)[3].next == "충분히 회복됐어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.")
    }

    @Test func lowRatioIsRestedRegardlessOfWeekOverWeek() {
        // 4주 평균 대비 낮음이면 최근 7일 증감이 커도 회복 국면
        var i = todayInput(); i.weekOverWeek = 0.40; i.acuteChronic = .low; i.acuteChronicYesterday = .low
        i.loadSentence = nil; i.daysSinceHardRun = 2; i.streakDays = 0; i.todayIsHard = false
        #expect(lines(i)[3].next == "충분히 회복됐어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.")
    }

    // MARK: 거리 적응 — 다음 롱런 거리를 정하는 주체

    @Test func distanceNextForPlannedLongRunIsRecovery() {
        // 거리주·롱런처럼 오늘 거리가 계획의 일부면 증량 규칙 대신 회복을 말한다
        #expect(lines(todayInput())[1].next == "계획한 거리를 채운 러닝이에요. 다음 1~2일은 이지런이나 휴식으로 회복하세요.")
    }

    @Test func distanceNextDefersToRacePlan() {
        var i = todayInput(); i.planPhase = "늘리기"
        #expect(lines(i)[1].next == "대회 훈련 계획상 늘리기 주의 러닝이에요. 다음 롱런 거리는 계획을 따르세요.")
    }

    @Test func distanceNextHoldsInPlanEasyWeek() {
        var i = todayInput(); i.planPhase = "회복"
        #expect(lines(i)[1].next == "대회 훈련 계획상 회복 주예요. 거리를 더 늘리지 말고 계획대로 가세요.")
    }

    @Test func distanceNextKeepsBuildRuleForUnplannedJump() {
        // 플랜도 없고 계획된 롱런 유형도 아닌데 평소의 두 배 — 이 줄이 원래 잡으려던 상황
        var i = todayInput(); i.workoutType = .general
        #expect(lines(i)[1].next == "이 거리는 2~3주 유지한 뒤 늘리세요. 롱런은 한 번에 평소의 1.3배 안에서.")
    }

    // MARK: 심박 — 플랜 이탈

    @Test func planEasyWeekHighIntensityIsFlagged() {
        // 회복 주에 Zone 3 이상 90% — 유형이 거리주(계획된 고강도)여도 플랜이 우선한다
        var i = todayInput(); i.planPhase = "회복"
        #expect(lines(i)[2].state == "회복 주인데 고강도 · Zone 3 이상 90%")
        #expect(lines(i)[2].evidence == "대회 훈련 계획상 회복 주 · Zone 4 62% · 평균 149 · 최고 157 · 25°C(더위 +8)")
        #expect(lines(i)[2].next == "회복 주는 다음 고강도를 받아낼 몸을 만드는 기간이에요. 다음 러닝은 이지런으로 돌아가세요.")
    }

    @Test func planEasyWeekEasyRunIsNotFlagged() {
        // 회복 주에 Zone 2 위주면 이탈이 아니다
        var i = todayInput(); i.planPhase = "회복"
        i.zoneFractions = [1: 0.15, 2: 0.70, 3: 0.15]
        #expect(lines(i)[2].state == "딱 좋은 강도")
        #expect(lines(i)[2].next == nil)
    }

    @Test func buildPhaseHighIntensityIsNotFlagged() {
        // 늘리기 주의 고강도는 계획대로다
        var i = todayInput(); i.planPhase = "늘리기"
        #expect(lines(i)[2].state == "계획대로 고강도")
    }

    @Test func planRecoveryPhaseOverrides() {
        var i = todayInput(); i.planPhase = "회복"
        #expect(lines(i)[3].next == "대회 훈련 계획상 회복 주예요. 이지런 위주로 가세요.")
    }

    @Test func planTaperPhaseOverrides() {
        var i = todayInput(); i.planPhase = "테이퍼"
        #expect(lines(i)[3].next == "대회 훈련 계획상 테이퍼 주예요. 이지런 위주로 가세요.")
    }

    @Test func restedNeedsLoadData() {
        // 결정 2: 4주 평균 대비(acuteChronic)도 7일 AU도 없으면 "충분히 회복됐다"고 말하지 않는다
        var i = todayInput()
        i.weekOverWeek = nil; i.acuteChronic = nil; i.sevenDayAU = nil; i.previousSevenAU = nil
        i.loadSentence = nil; i.daysSinceHardRun = 3; i.streakDays = 3
        #expect(lines(i)[3].next != "충분히 회복됐어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.")
    }

    @Test func heavierFormSuggestsWatchingLateStride() {
        var i = todayInput(); i.form = heavierForm10km()
        #expect(lines(i)[0].next == "다음 롱런은 같은 거리에서 후반 보폭만 지켜보세요.")
        #expect(lines(i)[0].evidence == "케이던스 175 유지 · 마지막 3km 보폭 0.85 범위 아래 · 지면접촉 272 범위 위")
    }

    @Test func heavierCadenceSuggestsWatchingCadence() {
        var i = todayInput(); i.form = heavierFormCadence10km()
        #expect(lines(i)[0].next == "다음 롱런은 같은 거리에서 후반 케이던스만 지켜보세요.")
    }

    @Test func unknownCadenceIsNotReported() {
        var i = RunSummaryInput(); i.form = heldFormUnknownCadence16km()
        #expect(lines(i).first?.evidence == "마지막 5km 보폭 0.92 범위 안 · 지면접촉 255 범위 안")
    }

    // MARK: 페이스 무너짐

    /// 10km 러닝: mid 5'55"(hr161·stride0.97·cad175·gct242) → late 6'30"(hr163·stride0.91·cad171·gct266) — `FormPhaseTests`의 픽스처와 같은 값.
    private func fadedForm10km() -> FormPhase.Result {
        let s = (1...3).map { SplitData(id: $0, distanceM: 1000, duration: 370, avgHeartRate: 144, avgCadence: 175, avgPower: nil, avgGroundContactTime: 255, avgStrideLength: 0.92, avgVerticalOscillation: 8.4) }
            + (4...7).map { SplitData(id: $0, distanceM: 1000, duration: 355, avgHeartRate: 161, avgCadence: 175, avgPower: nil, avgGroundContactTime: 242, avgStrideLength: 0.97, avgVerticalOscillation: 8.4) }
            + (8...10).map { SplitData(id: $0, distanceM: 1000, duration: 390, avgHeartRate: 163, avgCadence: 171, avgPower: nil, avgGroundContactTime: 266, avgStrideLength: 0.91, avgVerticalOscillation: 8.4) }
        return classify(s)!
    }

    @Test func fadedFormLineHasPacingNext() {
        var i = RunSummaryInput()
        i.form = fadedForm10km()
        i.isLongDistanceContext = true
        let line = lines(i)[0]
        #expect(line.state == "마지막 3km 페이스 떨어짐")
        #expect(line.tone == .neutral)
        #expect(line.evidence == "페이스 5'55\"→6'30\" · 보폭 0.97→0.91 · 케이던스 175→171 · 지면접촉 +24ms")
        #expect(line.next == "다음엔 중반을 10초/km 늦게 시작해 보세요.")
    }
}
