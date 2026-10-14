import Testing
import Foundation
@testable import MIMORunning

extension RunSummaryBuilder.Context {
    /// 오늘의 인사이트 요약 테스트용 — 빈 기록·옵셔널 모두 nil
    static func stub(workoutType: WorkoutType, hrZones: [HRZoneData] = [], hrSamples: [(offset: TimeInterval, bpm: Int)] = [],
                     detail: ActivityDetail? = nil, planPhase: String? = nil) -> Self {
        let a = Activity(id: UUID(), type: .running, date: Date(), duration: 3000, distance: 8000,
                         calories: nil, avgHeartRate: nil)
        return RunSummaryBuilder.Context(activity: a, detail: detail, history: [], hrZones: hrZones, hrSamples: hrSamples,
                                         formBaseline: nil, formShifts: [], workoutType: workoutType,
                                         workoutTypeFn: nil, effortIndex: nil, heatHRModel: nil,
                                         age: nil, isMale: nil, easyPaceLookup: nil, planPhase: planPhase,
                                         raceDetailFn: nil, hrZonesFn: nil)
    }
}

/// 리듬 카드 판정 추출(카드 = 요약 단일 출처) + 리듬 블록 신호
@Suite("TabDigestRhythm 리듬 판정·신호", .korean)
@MainActor
struct TabDigestRhythmTests {

    private func split(_ id: Int, pace: Double, cad: Int? = nil, gct: Double? = nil) -> SplitData {
        SplitData(id: id, distanceM: 1000, duration: pace,
                  avgHeartRate: 150, avgCadence: cad, avgPower: nil,
                  avgGroundContactTime: gct, avgStrideLength: nil, avgVerticalOscillation: nil)
    }

    private func zone(_ id: Int, _ f: Double) -> HRZoneData {
        HRZoneData(id: id, name: "Z\(id)", minBPM: 0, maxBPM: 0, seconds: f * 3000, fraction: f)
    }

    // MARK: 추출 회귀 — 카드가 내던 문장 그대로

    @Test func easyVerdictThresholds() {
        let good = TabDigestRhythm.easyVerdict(lowZoneFraction: 0.85)
        #expect(good.text == "제대로 이지 페이스를 지켰습니다")
        #expect(good.isProblem == false)
        #expect(good.isGood)
        let mid = TabDigestRhythm.easyVerdict(lowZoneFraction: 0.6)
        #expect(mid.text == "이지 구간이 60%였습니다. 조금 더 천천히 가도 좋습니다")
        #expect(mid.shade == .neutral)
        let high = TabDigestRhythm.easyVerdict(lowZoneFraction: 0.4)
        #expect(high.text == "이지런인데 심박이 꽤 높았습니다. 더 천천히 뛰어도 좋습니다")
        #expect(high.isProblem)
        #expect(high.shade == .caution)
    }

    @Test func zoneVerdictZone2() {
        let v = TabDigestRhythm.zoneVerdict(fractions: [2: 0.7, 3: 0.3], workoutType: .easy, heatSuffix: nil)
        #expect(v?.text == AppLanguage.shared.s("Zone 2 중심으로 달렸습니다", "Mostly in Zone 2", ja: "ゾーン2中心で走りました"))
        #expect(v?.isProblem == false)
    }

    @Test func zoneVerdictHighIntensityUnplannedIsProblem() {
        let v = TabDigestRhythm.zoneVerdict(fractions: [4: 0.5, 5: 0.2, 2: 0.3], workoutType: .general, heatSuffix: nil)
        #expect(v?.text == "고강도 구간이 많았습니다")
        #expect(v?.isProblem == true)
        let planned = TabDigestRhythm.zoneVerdict(fractions: [4: 0.5, 5: 0.2, 2: 0.3], workoutType: .tempo, heatSuffix: nil)
        #expect(planned?.text == "고강도 구간이 많았습니다 · 의도한 강도")
        #expect(planned?.isProblem == false)
    }

    @Test func zoneVerdictTempoZoneWithHeatSuffix() {
        let v = TabDigestRhythm.zoneVerdict(fractions: [3: 0.6, 2: 0.4], workoutType: .general, heatSuffix: " · 더위로 +6bpm")
        #expect(v?.text == "심박은 템포 구간에 머물렀습니다 · 더위로 +6bpm")
        #expect(v?.isProblem == true)
        let interval = TabDigestRhythm.zoneVerdict(fractions: [3: 0.6, 2: 0.4], workoutType: .interval, heatSuffix: nil)
        #expect(interval?.text == "운동·회복이 섞인 평균이 Zone 3입니다")
        #expect(interval?.isProblem == false)
    }

    @Test func paceShapeEvenIsGood() {
        let splits = (1...8).map { split($0, pace: 380) }
        let v = TabDigestRhythm.paceShapeVerdict(splits: splits, workoutType: .general)
        #expect(v?.text == "처음부터 끝까지 고르게 달렸습니다")
        #expect(v?.isProblem == false)
    }

    @Test func paceShapeGeneralSlowdownIsProblem() {
        let splits = [370.0, 372, 374, 376, 395, 400, 405, 410].enumerated().map { split($0.offset + 1, pace: $0.element) }
        let v = TabDigestRhythm.paceShapeVerdict(splits: splits, workoutType: .general)
        #expect(v?.text == "후반으로 갈수록 페이스가 느려졌습니다")
        #expect(v?.isProblem == true)
        #expect(v?.shade == .neutral)
    }

    @Test func paceShapeDistanceRunBigDrop() {
        let splits = [300.0, 300, 300, 300, 330, 330, 330, 330].enumerated().map { split($0.offset + 1, pace: $0.element) }
        let v = TabDigestRhythm.paceShapeVerdict(splits: splits, workoutType: .distanceRun)
        #expect(v?.text == "후반 페이스가 많이 떨어졌습니다. 초반이 빨랐을 수 있습니다")
        #expect(v?.isProblem == true)
        #expect(v?.shade == .caution)
        let held = [300.0, 300, 300, 300, 298, 298, 298, 298].enumerated().map { split($0.offset + 1, pace: $0.element) }
        #expect(TabDigestRhythm.paceShapeVerdict(splits: held, workoutType: .distanceRun)?.text == "후반에도 페이스가 떨어지지 않았습니다")
    }

    @Test func typeFormTempoGCTRise() {
        let splits = (1...6).map { split($0, pace: 300, gct: $0 <= 3 ? 230 : 240) }
        let v = TabDigestRhythm.typeFormVerdict(workoutType: .tempo, splits: splits, formBaseline: nil)
        #expect(v?.text == "후반에 지면접촉이 +10ms 늘었습니다. 템포 페이스가 살짝 빠를 수 있습니다")
        #expect(v?.isProblem == true)
        // 리듬 신호로는 나오지 않는다(폼 탭 몫)
        #expect(TabDigestRhythm.paceShapeVerdict(splits: splits, workoutType: .tempo) == nil)
    }

    @Test func distanceRankPhrase() {
        #expect(TabDigestRhythm.distanceRankPhrase(rank: 1, sampleCount: 10) == "최근 10회 중 가장 긴 거리")
        #expect(TabDigestRhythm.distanceRankPhrase(rank: 2, sampleCount: 10) == "최근 10회 중 2번째로 긴 거리")
        #expect(TabDigestRhythm.distanceRankPhrase(rank: 4, sampleCount: 10) == nil)
    }

    // MARK: 신호

    @Test func easyRunHighHRBecomesProblemWithNext() {
        var i = RunSummaryInput(); i.workoutType = .easy; i.zoneFractions = [3: 0.6, 2: 0.4]; i.distKm = 8
        let lines = RunSummary.lines(i)
        let sig = TabDigestRhythm.signals(context: .stub(workoutType: .easy), input: i, lines: lines)
        let p = sig.first { $0.kind == .problem }
        #expect(p?.priority == 1)
        #expect(p?.tab == .rhythm)
        #expect(p?.tone == .caution)
        #expect(p?.text.hasPrefix("이지런 기준 높음") == true)
        #expect(p?.direction != nil)
    }

    @Test func planEasyWeekHighIntensityIsPriority2() {
        var i = RunSummaryInput(); i.workoutType = .tempo; i.zoneFractions = [4: 0.6, 2: 0.4]; i.distKm = 8; i.planPhase = "회복"
        let lines = RunSummary.lines(i)
        let sig = TabDigestRhythm.signals(context: .stub(workoutType: .tempo, planPhase: "회복"), input: i, lines: lines)
        #expect(sig.first { $0.kind == .problem }?.priority == 2)
    }

    @Test func unplannedHighZoneIsR5() {
        let zones = [zone(4, 0.5), zone(5, 0.2), zone(2, 0.3)]
        var i = RunSummaryInput(); i.workoutType = .general; i.zoneFractions = [4: 0.5, 5: 0.2, 2: 0.3]; i.distKm = 8
        let sig = TabDigestRhythm.signals(context: .stub(workoutType: .general, hrZones: zones), input: i, lines: RunSummary.lines(i))
        let p = sig.first { $0.kind == .problem }
        #expect(p?.priority == 5)
        #expect(p?.text == "고강도 구간이 많았습니다")
    }

    @Test func distanceRankGoodSignal() {
        var i = RunSummaryInput(); i.distanceRank = 1; i.distanceSampleCount = 10; i.distKm = 8
        let sig = TabDigestRhythm.signals(context: .stub(workoutType: .general), input: i, lines: [])
        let g = sig.first { $0.family == .distanceRank }
        #expect(g?.kind == .good)
        #expect(g?.text == "최근 10회 중 가장 긴 거리")
    }

    private func detail(_ splits: [SplitData]) -> ActivityDetail {
        ActivityDetail(routeCoordinates: [], routeTimeOffsets: [], elevationGain: 0,
                       avgPower: nil, avgCadence: nil, splits: splits, hrZones: [],
                       intervalSegments: [], workoutType: .general,
                       avgGroundContactTime: nil, avgStrideLength: nil,
                       avgVerticalOscillation: nil, vo2Max: nil,
                       altitudeProfile: [], altitudeTimeProfile: [])
    }

    private func paceSignals(_ paces: [Double], type: WorkoutType) -> [TabDigest.Signal] {
        let splits = paces.enumerated().map { split($0.offset + 1, pace: $0.element) }
        var i = RunSummaryInput(); i.workoutType = type; i.distKm = Double(paces.count)
        return TabDigestRhythm.signals(context: .stub(workoutType: type, detail: detail(splits)), input: i, lines: [])
            .filter { $0.priority == 6 && $0.kind == .problem }
    }

    @Test func generalSlowdownIsNotRhythmSignal() {
        #expect(paceSignals([370, 372, 374, 376, 395, 400, 405, 410], type: .general).isEmpty)
    }

    @Test func distanceRunBigDropIsLatePaceProblem() {
        let s = paceSignals([300, 300, 300, 300, 330, 330, 330, 330], type: .distanceRun)
        #expect(s.count == 1)
        #expect(s.first?.family == .latePace)
        #expect(s.first?.text == "후반 페이스가 많이 떨어졌습니다. 초반이 빨랐을 수 있습니다")
    }

    @Test func generalVariedPaceIsUniqueProblem() {
        let s = paceSignals([300, 360, 300, 360, 300, 360, 300, 360], type: .general)
        #expect(s.count == 1)
        #expect(s.first?.family == .unique)
        #expect(s.first?.text == "페이스 기복이 있었습니다")
    }

    /// 빌드업은 후반 심박 상승이 계획 — 캡션은 유형 문구로 나오지만 문제 신호는 아니다
    @Test func buildUpSecondHalfRiseIsNotProblem() {
        let samples: [(offset: TimeInterval, bpm: Int)] = (0..<40).map { (offset: Double($0) * 30, bpm: $0 < 20 ? 140 : 155) }
        let ctx = RunSummaryBuilder.Context.stub(workoutType: .buildUp, hrSamples: samples)
        let cap = TabDigestRhythm.hrVerdict(samples: samples, hrMax: nil, age: nil, workoutType: .buildUp,
                                            activity: ctx.activity, detail: nil, history: [])
        #expect(cap?.kind == .secondHalfRise)
        #expect(cap?.text == "후반에 페이스를 올려 심박도 올랐습니다")
        var i = RunSummaryInput(); i.workoutType = .buildUp; i.distKm = 8
        let sig = TabDigestRhythm.signals(context: ctx, input: i, lines: [])
        #expect(!sig.contains { $0.priority == 4 && $0.kind == .problem })
        // 같은 샘플이라도 일반 러닝이면 문제 p4
        let gen = TabDigestRhythm.signals(context: .stub(workoutType: .general, hrSamples: samples), input: RunSummaryInput(), lines: [])
        #expect(gen.contains { $0.priority == 4 && $0.kind == .problem && $0.family == .lateHR })
    }

    @Test func defaultDirectionIsDistanceLineNext() {
        let lines = [RunSummaryLine(axis: "심박", state: "x", tone: .good, next: "a"),
                     RunSummaryLine(axis: "거리 적응", state: "y", tone: .good, next: "b")]
        #expect(TabDigestRhythm.defaultDirection(lines: lines) == "b")
    }
}
