import Testing
import Foundation
@testable import MIMORunning

/// 퍼포먼스 카드 판정 추출(카드 = 요약 단일 출처) + 퍼포먼스 블록 신호
@Suite("TabDigestPerformance 퍼포먼스 판정·신호", .korean)
@MainActor
struct TabDigestPerformanceTests {

    // MARK: 추출 회귀 — 카드가 내던 문장 그대로

    @Test func decouplingVerdictBoundaries() {
        let ok = TabDigestPerformance.decouplingVerdict(pct: 4.9, workoutType: .longRun, temperatureC: nil, lateHRRoseFirst: false)
        #expect(ok.text == "후반까지 페이스 대비 심박을 지켰습니다. 이 거리를 유산소로 감당했습니다.")
        #expect(ok.isProblem == false)
        #expect(ok.isGood)
        let okTempo = TabDigestPerformance.decouplingVerdict(pct: 4.9, workoutType: .tempo, temperatureC: 26, lateHRRoseFirst: false)
        #expect(okTempo.text == "후반까지 페이스 대비 심박을 지켰습니다. 이 페이스로 이 거리를 버틸 힘이 있습니다.")
        let lateRose = TabDigestPerformance.decouplingVerdict(pct: 4.9, workoutType: .longRun, temperatureC: nil, lateHRRoseFirst: true)
        #expect(lateRose.text == "전후반으로는 5% 안이지만, 마지막 구간에서 같은 페이스에 심박이 올랐습니다.")
        #expect(lateRose.isProblem == false)
        #expect(lateRose.isGood == false)

        let mid = TabDigestPerformance.decouplingVerdict(pct: 7, workoutType: .longRun, temperatureC: 15, lateHRRoseFirst: false)
        #expect(mid.text == "조건은 좋았는데 후반에 심박이 올랐습니다. 이 거리와 강도가 아직 조금 부담일 수 있습니다.")
        #expect(mid.isProblem)
        #expect(mid.shade == .neutral)
        let midHot = TabDigestPerformance.decouplingVerdict(pct: 7, workoutType: .longRun, temperatureC: 26, lateHRRoseFirst: false)
        #expect(midHot.text == "후반에 심박이 올랐지만 더운 날이라 자연스러운 범위입니다.")
        #expect(midHot.isProblem == false)

        let big = TabDigestPerformance.decouplingVerdict(pct: 12, workoutType: .longRun, temperatureC: nil, lateHRRoseFirst: false)
        #expect(big.text == "후반에 심박이 많이 올랐습니다. 이 거리와 강도가 아직 버겁거나 초반이 빨랐을 수 있습니다.")
        #expect(big.isProblem)
        #expect(big.shade == .caution)
        let bigHot = TabDigestPerformance.decouplingVerdict(pct: 12, workoutType: .longRun, temperatureC: 26, lateHRRoseFirst: false)
        #expect(bigHot.text == "후반에 심박이 많이 올랐습니다. 더위와 수분 부족이 컸을 것입니다.")
        #expect(bigHot.isProblem == false)
        #expect(bigHot.shade == .caution)

        let buildUp = TabDigestPerformance.decouplingVerdict(pct: 12, workoutType: .buildUp, temperatureC: nil, lateHRRoseFirst: false)
        #expect(buildUp.text == "후반 페이스를 올린 만큼 심박도 올랐습니다.")
        #expect(buildUp.isProblem == false)
    }

    @Test func decouplingPctGates() {
        let splits = (1...10).map { i in
            SplitData(id: i, distanceM: 1000, duration: 360, avgHeartRate: i <= 5 ? 140 : 150, avgCadence: nil,
                      avgPower: nil, avgGroundContactTime: nil, avgStrideLength: nil, avgVerticalOscillation: nil)
        }
        #expect(TabDigestPerformance.decouplingPct(splits: splits, workoutType: .interval, distKm: 10) == nil)
        #expect(TabDigestPerformance.decouplingPct(splits: splits, workoutType: .general, distKm: 9.0) == nil)
        let pct = TabDigestPerformance.decouplingPct(splits: splits, workoutType: .general, distKm: 10)
        #expect(pct != nil && abs(pct! - (1 - 140.0 / 150.0) * 100) < 0.01)
    }

    /// `SentenceKind`에는 '유지'가 없다(엔진이 nil로 침묵) — 네 경우 모두 문장이 있다.
    @Test func loadTexts() {
        #expect(TabDigestPerformance.loadRatioText(.veryHigh) == "4주 평균 대비 크게 높음")
        #expect(TabDigestPerformance.loadSentence(.monotony) == "부하 편차 적음 — 강약 나누기")
        #expect(TabDigestPerformance.loadSentence(.low) == "회복 방향으로 진행 중")
        #expect(TabDigestPerformance.loadLine(ratio: "4주 평균 대비 높음", sentence: "부하 조금 높은 편") == "4주 평균 대비 높음, 부하 조금 높은 편")
        #expect(TabDigestPerformance.loadLine(ratio: nil, sentence: nil) == nil)
    }

    @Test func easyAlertText() {
        #expect(TabDigestPerformance.easyAlertText(weeks: 4, classified: 11, easyCount: 0, easyStreak: 4, easyStreakAtLeast: false) == nil)
        #expect(TabDigestPerformance.easyAlertText(weeks: 4, classified: 14, easyCount: 2, easyStreak: 3, easyStreakAtLeast: false)
                == "4주 14회 중 이지런 2회 · 이지런 없는 주 3주째")
    }

    // MARK: 신호

    private func detail(_ splits: [SplitData]) -> ActivityDetail {
        ActivityDetail(routeCoordinates: [], routeTimeOffsets: [], elevationGain: 0,
                       avgPower: nil, avgCadence: nil, splits: splits, hrZones: [],
                       intervalSegments: [], workoutType: .longRun,
                       avgGroundContactTime: nil, avgStrideLength: nil,
                       avgVerticalOscillation: nil, vo2Max: nil,
                       altitudeProfile: [], altitudeTimeProfile: [])
    }

    private var loadLines: [RunSummaryLine] {
        [RunSummaryLine(axis: RunHeadline.Axis.load.label!, state: "부하가 크게 늘었습니다", tone: .neutral,
                        next: "다음 이틀은 가볍게 달리세요")]
    }

    @Test func veryHighLoadIsProblemWithLoadDirection() {
        var i = RunSummaryInput()
        i.acuteChronic = .veryHigh
        i.loadSentence = .veryHigh
        let s = TabDigestPerformance.signals(context: .stub(workoutType: .general), input: i, lines: loadLines,
                                             insights: [], easyAlertText: nil)
        let p2 = s.first { $0.kind == .problem && $0.priority == 2 }
        #expect(p2?.family == .load)
        #expect(p2?.text == "4주 평균 대비 크게 높음, 부하 크게 증가 중 — 회복 챙기기")
        #expect(p2?.direction == loadLines[0].next)
        #expect(p2?.tab == .performance)
        #expect(TabDigestPerformance.defaultDirection(lines: loadLines) == loadLines[0].next)
    }

    @Test func decouplingSignalIsLateHR() {
        let splits = (1...10).map { i in
            SplitData(id: i, distanceM: 1000, duration: 360, avgHeartRate: i <= 5 ? 140 : 155, avgCadence: nil,
                      avgPower: nil, avgGroundContactTime: nil, avgStrideLength: nil, avgVerticalOscillation: nil)
        }
        let s = TabDigestPerformance.signals(context: .stub(workoutType: .longRun, detail: detail(splits)),
                                             input: RunSummaryInput(), lines: [], insights: [], easyAlertText: nil)
        let p3 = s.first { $0.priority == 3 && $0.kind == .problem }
        #expect(p3?.family == .lateHR)
        #expect(p3?.text == "조건은 좋았는데 후반에 심박이 올랐습니다. 이 거리와 강도가 아직 조금 부담일 수 있습니다.")
    }

    @Test func insightsMapToProblemsAndGood() {
        let higher = RunInsight(category: .efficiency, tone: .neutral, badge: "참고", message: "심박이 5bpm 높습니다.",
                                highlights: [], source: .efficiencyComparisonHigher)
        let drift = RunInsight(category: .efficiency, tone: .neutral, badge: "참고", message: "드리프트", highlights: [])
        let fade = RunInsight(category: .endurance, tone: .caution, badge: "참고", message: "후반 페이스가 전반보다 7.0% 느려졌습니다.", highlights: [])
        let s = TabDigestPerformance.signals(context: .stub(workoutType: .general), input: RunSummaryInput(), lines: [],
                                             insights: [drift, higher, fade], easyAlertText: "4주 14회 중 이지런 2회")
        #expect(s.first { $0.priority == 4 }?.family == .efficiency)
        #expect(s.first { $0.priority == 4 }?.text == "심박이 5bpm 높습니다.")
        #expect(s.first { $0.priority == 5 }?.text == "4주 14회 중 이지런 2회")
        #expect(s.first { $0.priority == 6 }?.family == .latePace)
        #expect(!s.contains { $0.text == "드리프트" })

        let lower = RunInsight(category: .efficiency, tone: .good, badge: "효율 향상", message: "심박이 4bpm 낮았습니다.",
                               highlights: [], source: .efficiencyComparison)
        let g = TabDigestPerformance.signals(context: .stub(workoutType: .general), input: RunSummaryInput(), lines: [],
                                             insights: [lower], easyAlertText: nil)
        #expect(g.count == 1 && g[0].kind == .good && g[0].family == .efficiency)
    }

    // MARK: 디커플링 신호 — 값이 있으면 .lateHR 1개 (fix round 1)

    private func decouplingContext(back: Int, tempC: Double?) -> RunSummaryBuilder.Context {
        let splits = (1...10).map { i in
            SplitData(id: i, distanceM: 1000, duration: 360, avgHeartRate: i <= 5 ? 140 : back, avgCadence: nil,
                      avgPower: nil, avgGroundContactTime: nil, avgStrideLength: nil, avgVerticalOscillation: nil)
        }
        let base = RunSummaryBuilder.Context.stub(workoutType: .longRun, detail: detail(splits))
        let a = Activity(id: UUID(), type: .running, date: Date(), duration: 3600, distance: 10_000,
                         calories: nil, avgHeartRate: nil, temperatureC: tempC)
        return RunSummaryBuilder.Context(activity: a, detail: base.detail, history: [], hrZones: [], hrSamples: [],
                                         formBaseline: nil, formShifts: [], workoutType: .longRun,
                                         workoutTypeFn: nil, effortIndex: nil, heatHRModel: nil,
                                         age: nil, isMale: nil, easyPaceLookup: nil, planPhase: nil,
                                         raceDetailFn: nil, hrZonesFn: nil)
    }

    /// 더운 날 12%(주의색) → 문제 p3
    @Test func hotBigDecouplingIsProblem() {
        // 140 → 160: (1 − 140/160) = 12.5%
        let s = TabDigestPerformance.signals(context: decouplingContext(back: 160, tempC: 26), input: RunSummaryInput(),
                                             lines: [], insights: [], easyAlertText: nil)
        let late = s.filter { $0.family == .lateHR }
        #expect(late.count == 1)
        #expect(late.first?.kind == .problem && late.first?.priority == 3 && late.first?.tone == .caution)
        #expect(late.first?.text == "후반에 심박이 많이 올랐습니다. 더위와 수분 부족이 컸을 것입니다.")
    }

    /// 더운 날 7% → 중립 덧붙임(extra) p1 — 좋은 신호에 밀려 사라지지 않게
    @Test func hotMidDecouplingIsNeutralExtra() {
        // 140 → 151: (1 − 140/151) ≈ 7.3%
        let s = TabDigestPerformance.signals(context: decouplingContext(back: 151, tempC: 26), input: RunSummaryInput(),
                                             lines: [], insights: [], easyAlertText: nil)
        let late = s.filter { $0.family == .lateHR }
        #expect(late.count == 1)
        #expect(late.first?.kind == .extra && late.first?.priority == 1 && late.first?.tone == .neutral)
        #expect(late.first?.text == "후반에 심박이 올랐지만 더운 날이라 자연스러운 범위입니다.")
    }

    /// 조합기 — 퍼포먼스 중립 디커플링이 있으면 리듬 R4(.lateHR)는 리듬 블록에 나오지 않는다
    @Test func neutralDecouplingOwnsLateHROverRhythm() {
        let perf = TabDigestPerformance.signals(context: decouplingContext(back: 151, tempC: 26), input: RunSummaryInput(),
                                                lines: [], insights: [], easyAlertText: nil)
        let r4 = TabDigest.Signal(tab: .rhythm, kind: .problem, priority: 4, family: .lateHR,
                                  text: "후반에 심박이 올랐습니다", tone: .caution)
        let blocks = TabDigest.make([r4] + perf)
        let rhythm = blocks.first { $0.tab == .rhythm }
        #expect(rhythm?.statements.contains { $0.text == r4.text } != true)
        #expect(blocks.first { $0.tab == .performance }?.statements.contains {
            $0.text == "후반에 심박이 올랐지만 더운 날이라 자연스러운 범위입니다."
        } == true)
    }

    // MARK: 요약 개조식(short)

    private func isTerse(_ s: String?) -> Bool {
        guard let s, !s.isEmpty else { return false }
        return !s.contains("습니다")
    }

    @Test func performanceShortsAreTerse() {
        var i = RunSummaryInput()
        i.acuteChronic = .veryHigh
        i.loadSentence = .veryHigh
        let s = TabDigestPerformance.signals(context: .stub(workoutType: .general), input: i, lines: loadLines,
                                             insights: [], easyAlertText: nil)
        let p2 = s.first { $0.kind == .problem && $0.priority == 2 }
        #expect(p2?.short == "강도 부하 4주 평균 대비 크게 높음 · 급증")

        let splits = (1...10).map { i in
            SplitData(id: i, distanceM: 1000, duration: 360, avgHeartRate: i <= 5 ? 140 : 155, avgCadence: nil,
                      avgPower: nil, avgGroundContactTime: nil, avgStrideLength: nil, avgVerticalOscillation: nil)
        }
        let d = TabDigestPerformance.signals(context: .stub(workoutType: .longRun, detail: detail(splits)),
                                             input: RunSummaryInput(), lines: [], insights: [], easyAlertText: nil)
        let p3 = d.first { $0.priority == 3 && $0.kind == .problem }
        #expect(isTerse(p3?.short))
        #expect(p3?.short?.hasPrefix("디커플링") == true)
    }
}
