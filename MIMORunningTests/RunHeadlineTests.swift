import Testing
import Foundation
@testable import MIMORunning

@Suite("오늘의 인사이트 — 카드 판정 요약", .korean)
struct RunHeadlineTests {
    // 총평 줄 픽스처 — 축 라벨은 RunSummary와 같은 한국어
    private func line(_ axis: String, _ state: String, _ tone: RunSummaryLine.Tone = .good, next: String? = nil) -> RunSummaryLine {
        var l = RunSummaryLine(axis: axis, state: state, tone: tone); l.next = next; return l
    }
    private let taperNext = "대회 훈련 계획상 테이퍼 주입니다. 이지런 위주로 가세요."
    private var todayLines: [RunSummaryLine] {
        [line("러닝폼", "끝까지 유지"), line("심박", "Zone 2 중심"),
         line("훈련부하", "4주 평균 수준 · 4일 연속", next: taperNext), line("유산소", "50대 남성 기준 높음")]
    }
    private var efficiency7: RunInsight {
        RunInsight(category: .efficiency, tone: .good, badge: "효율 향상",
                   message: "비슷한 페이스 최근 8주 5회보다 심박이 7 bpm 낮았습니다.", highlights: ["7bpm", "5회"])
    }
    private func input(km: Double = 6.24, late: FormPhase.Late? = .held, type: WorkoutType = .general,
                       ac: EffortLoad.RatioLabel? = .steady, streak: Int = 0, plan: String? = nil,
                       rank: Int? = nil, samples: Int? = nil) -> RunSummaryInput {
        var i = RunSummaryInput()
        i.distKm = km; i.workoutType = type; i.acuteChronic = ac; i.streakDays = streak; i.planPhase = plan
        i.distanceRank = rank; i.distanceSampleCount = samples
        if let late { i.form = .stub(late: late) }
        return i
    }
    private let streakInsight = InsightResult(theme: .distanceExpanded, title: "경계를 넓힌 러닝", detail: "이번 주 최장 거리 6.24 km")

    @Test func todayExampleSummarizesCards() {
        // 9/29 — 심박 효율(1순위) · 폼 유지(6km라 제목 후보 아님, 두 번째 사실) · 테이퍼 주
        let h = RunHeadline.make(insight: streakInsight, summaryInput: input(streak: 4, plan: "테이퍼"),
                                 summaryLines: todayLines, efficiency: efficiency7)
        #expect(h?.title == "가벼워진 러닝")
        #expect(h?.fact == "같은 페이스에 심박 7bpm 낮음 · 폼은 끝까지 평소 범위")
        #expect(h?.next == taperNext)
        #expect(h?.source == .goodSignal)
    }

    @Test func rareEventComesFirstWithoutSecondFact() {
        let pr = InsightResult(theme: .recordImproved, title: "어제보다 나은 러닝", detail: "10K 90일 최고 페이스")
        let h = RunHeadline.make(insight: pr, summaryInput: input(), summaryLines: todayLines, efficiency: efficiency7)
        #expect(h?.title == "어제보다 나은 러닝")
        #expect(h?.fact == "10K 90일 최고 페이스")
        #expect(h?.source == .rareEvent)
    }

    @Test func restSignalBeatsGoodSignal() {
        var lines = todayLines
        lines[2] = line("훈련부하", "4주 평균 대비 높음", .neutral, next: "다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋습니다.")
        let h = RunHeadline.make(insight: nil, summaryInput: input(ac: .high), summaryLines: lines, efficiency: efficiency7)
        #expect(h?.title == "쌓이는 러닝")
        #expect(h?.fact == "4주 평균 대비 높음 · 같은 페이스에 심박 7bpm 낮음")
        #expect(h?.next == "다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋습니다.")
    }

    @Test func mildCautionComesAfterGoodSignal() {
        let h = RunHeadline.make(insight: nil, summaryInput: input(km: 11, late: .heavier([.stride])),
                                 summaryLines: todayLines, efficiency: efficiency7)
        #expect(h?.title == "가벼워진 러닝")
        #expect(h?.fact.hasSuffix(" · 마지막 4km 살짝 무거워짐") == true)
    }

    @Test func heldFormTitlesOnlyFromEightKm() {
        let long = RunHeadline.make(insight: nil, summaryInput: input(km: 11), summaryLines: todayLines, efficiency: nil)
        #expect(long?.title == "끝까지 버틴 러닝")
        let short = RunHeadline.make(insight: streakInsight, summaryInput: input(km: 6), summaryLines: todayLines, efficiency: nil)
        #expect(short?.title != "끝까지 버틴 러닝")
    }

    @Test func secondFactSkipsSameAxis() {
        // 부하 급증 + 4일 연속(계획 없음) — 둘 다 훈련부하 축이라 두 번째 사실로 붙지 않는다
        var lines = todayLines
        lines[2] = line("훈련부하", "4주 평균 대비 높음 · 4일 연속", .neutral)
        let h = RunHeadline.make(insight: nil, summaryInput: input(late: nil, ac: .high, streak: 4),
                                 summaryLines: lines, efficiency: nil)
        #expect(h?.fact == "4주 평균 대비 높음 · 4일 연속")
    }

    @Test func nextActionFallsBackThroughAxes() {
        // 심박 축 next 없음 → 훈련부하 next
        let h1 = RunHeadline.make(insight: nil, summaryInput: input(), summaryLines: todayLines, efficiency: efficiency7)
        #expect(h1?.next == taperNext)
        // 같은 축(심박)에 next가 있으면 그것
        var lines = todayLines
        lines[1] = line("심박", "Zone 2 중심", next: "다음 이지런은 6'40\"로.")
        let h2 = RunHeadline.make(insight: nil, summaryInput: input(), summaryLines: lines, efficiency: efficiency7)
        #expect(h2?.next == "다음 이지런은 6'40\"로.")
        // 어디에도 next 없음 → nil
        let bare = [line("러닝폼", "끝까지 유지"), line("심박", "Zone 2 중심")]
        let h3 = RunHeadline.make(insight: nil, summaryInput: input(), summaryLines: bare, efficiency: efficiency7)
        #expect(h3?.next == nil)
    }

    @Test func fewSummaryLinesFallBackToEngine() {
        let h = RunHeadline.make(insight: streakInsight, summaryInput: input(), summaryLines: [line("심박", "Zone 2 중심")],
                                 efficiency: efficiency7)
        #expect(h?.title == "경계를 넓힌 러닝")
        #expect(h?.fact == "이번 주 최장 거리 6.24 km")
        #expect(h?.source == .fallback)
        #expect(RunHeadline.make(insight: nil, summaryInput: nil, summaryLines: [], efficiency: nil) == nil)
    }

    @Test func taperWeekIsContextTitleWhenNothingElse() {
        let h = RunHeadline.make(insight: streakInsight, summaryInput: input(km: 6, late: nil, plan: "테이퍼"),
                                 summaryLines: todayLines, efficiency: nil)
        #expect(h?.title == "숨 고르는 러닝")
        #expect(h?.fact == "대회 계획 테이퍼 주")
    }

    // MARK: - 역치 (2026-10-01)

    @Test func thresholdRaiseLeadsGoodSignals() {
        // 직전 5'05" → 직후 4'58" (7초 빨라짐) — 효율 신호보다 앞
        let t = RunHeadline.ThresholdContext(beforePace: 305, afterPace: 298, tempoGapSec: nil)
        let h = RunHeadline.make(insight: nil, summaryInput: input(late: nil), summaryLines: todayLines,
                                 efficiency: efficiency7, threshold: t)
        #expect(h?.title == "역치를 밀어올린 러닝")
        #expect(h?.fact == "역치 페이스 추정 5'05\" → 4'58\" · 같은 페이스에 심박 7bpm 낮음")
        #expect(h?.source == .goodSignal)
    }

    @Test func thresholdGainBelowCutoffIsNoCandidate() {
        let t = RunHeadline.ThresholdContext(beforePace: 300, afterPace: 298, tempoGapSec: nil)
        let c = RunHeadline.candidates(insight: nil, input: input(late: nil), lines: todayLines,
                                       efficiency: nil, threshold: t)
        #expect(c.isEmpty)
    }

    @Test func tempoGapIsSecondFactOnly() {
        // 템포런 + 효율 신호 — 제목은 효율, 두 번째 사실에 역치 대비 줄(같은 심박 축 "한계를 미는"은 건너뜀)
        let slow = RunHeadline.ThresholdContext(beforePace: 300, afterPace: 300, tempoGapSec: 4.2)
        let h = RunHeadline.make(insight: nil, summaryInput: input(late: nil, type: .tempo), summaryLines: todayLines,
                                 efficiency: efficiency7, threshold: slow)
        #expect(h?.title == "가벼워진 러닝")
        #expect(h?.fact == "같은 페이스에 심박 7bpm 낮음 · 본인 역치 대비 +4초/km")
        // 빠르면 −, 1초 미만이면 "그대로"
        let fast = RunHeadline.candidates(insight: nil, input: input(late: nil, type: .tempo), lines: todayLines,
                                          efficiency: nil, threshold: .init(tempoGapSec: -6))
        #expect(fast.contains { $0.fact == "본인 역치 대비 −6초/km" && !$0.titleEligible })
        let same = RunHeadline.candidates(insight: nil, input: input(late: nil, type: .tempo), lines: todayLines,
                                          efficiency: nil, threshold: .init(tempoGapSec: 0.4))
        #expect(same.contains { $0.fact == "본인 역치 페이스 그대로" })
        // 템포런이 아니면 없음
        let general = RunHeadline.candidates(insight: nil, input: input(late: nil), lines: todayLines,
                                             efficiency: nil, threshold: .init(tempoGapSec: 4.2))
        #expect(general.isEmpty)
    }

    @Test func nilThresholdKeepsExistingResult() {
        let base = RunHeadline.make(insight: streakInsight, summaryInput: input(streak: 4, plan: "테이퍼"),
                                    summaryLines: todayLines, efficiency: efficiency7)
        let withNil = RunHeadline.make(insight: streakInsight, summaryInput: input(streak: 4, plan: "테이퍼"),
                                       summaryLines: todayLines, efficiency: efficiency7, threshold: nil)
        let withEmpty = RunHeadline.make(insight: streakInsight, summaryInput: input(streak: 4, plan: "테이퍼"),
                                         summaryLines: todayLines, efficiency: efficiency7, threshold: .init())
        #expect(base == withNil)
        #expect(base == withEmpty)
    }
}
