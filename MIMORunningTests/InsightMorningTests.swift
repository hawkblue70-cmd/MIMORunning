import Testing
import Foundation
@testable import MIMORunning

@Suite("인사이트 내보내기 아침 제안 조립", .korean)
struct InsightMorningTests {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }

    /// 2026-10-14 07:00 KST 러닝
    private var runStart: Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 7))!
    }
    private func at(day: Int, hour: Int, minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func snap(_ key: String, level: String = "easy", line: String = "오늘은 이지런",
                      why: String = "연속 4일째입니다. 강도를 빼고 몸을 풀어 주세요.", at: Date) -> MRReadinessSnapshot {
        MRReadinessSnapshot(dateKey: key, level: level, line: line, why: why, data: "HRV 42ms",
                            planLine: "", computedAt: at)
    }

    private func readiness(_ level: MRReadiness.Level, pending: Bool = false,
                           why: String = "어젯밤 HRV가 평소 범위입니다. 계획대로 하세요.") -> MRReadiness {
        MRReadiness(level: level, reasons: [], hrvPending: pending, why: why, data: ["HRV 45ms", "연속 1일"])
    }

    @Test func snapshotBeforeRunIsPreferred() {
        let key = MRReadinessSnapshot.key(for: runStart, calendar: cal)
        var recomputed = 0
        let m = InsightMorning.make(
            runStart: runStart, now: at(day: 14, hour: 9),
            snapshotFor: { $0 == key ? snap(key, at: at(day: 14, hour: 6)) : nil },
            recompute: { _ in recomputed += 1; return readiness(.go) },
            firstRunStart: { _ in nil },
            actual: "이지 페이스 유지", direction: "내일은 쉬어 가세요", calendar: cal)
        #expect(m.morningOf?.level == "easy")
        #expect(m.morningOf?.why == "연속 4일째입니다.")
        #expect(m.morningOf?.data == "HRV 42ms")
        #expect(m.actual == "이지 페이스 유지")
        #expect(recomputed == 0)
    }

    @Test func snapshotAfterRunStartIsIgnored() {
        let key = MRReadinessSnapshot.key(for: runStart, calendar: cal)
        var asOfs: [Date] = []
        let m = InsightMorning.make(
            runStart: runStart, now: at(day: 14, hour: 9),
            snapshotFor: { $0 == key ? snap(key, at: at(day: 14, hour: 8)) : nil },
            recompute: { d in asOfs.append(d); return readiness(.go) },
            firstRunStart: { _ in nil },
            actual: nil, direction: nil, calendar: cal)
        #expect(m.morningOf?.level == "go")
        #expect(asOfs == [runStart.addingTimeInterval(-1)])
    }

    @Test func nextDayBeforeMidnightGivesDirection() {
        var asOfs: [Date] = []
        let m = InsightMorning.make(
            runStart: at(day: 14, hour: 19), now: at(day: 14, hour: 21),
            snapshotFor: { _ in nil },
            recompute: { d in asOfs.append(d); return readiness(.easy) },
            firstRunStart: { _ in nil },
            actual: nil, direction: "내일은 쉬어 가세요", calendar: cal)
        #expect(m.nextMorning == nil)
        #expect(m.nextDirection == "내일은 쉬어 가세요")
        #expect(asOfs.count == 1)   // 그날 아침만 재계산
    }

    @Test func nextDayPendingGivesDirection() {
        let m = InsightMorning.make(
            runStart: runStart, now: at(day: 15, hour: 6),
            snapshotFor: { _ in nil },
            recompute: { d in d > at(day: 15, hour: 0) ? readiness(.go, pending: true) : readiness(.easy) },
            firstRunStart: { _ in nil },
            actual: nil, direction: "내일은 쉬어 가세요", calendar: cal)
        #expect(m.morningOf?.level == "easy")
        #expect(m.nextMorning == nil)
        #expect(m.nextDirection == "내일은 쉬어 가세요")
    }

    @Test func nextDayRecomputeUsesEarliestAsOf() {
        var asOfs: [Date] = []
        let nextRun = at(day: 15, hour: 6, minute: 30)
        let m = InsightMorning.make(
            runStart: runStart, now: at(day: 15, hour: 20),
            snapshotFor: { _ in nil },
            recompute: { d in asOfs.append(d); return readiness(.go) },
            firstRunStart: { d in cal.isDate(d, inSameDayAs: nextRun) ? nextRun : nil },
            actual: nil, direction: "내일은 쉬어 가세요", calendar: cal)
        #expect(m.nextMorning?.level == "go")
        #expect(m.nextDirection == nil)
        #expect(asOfs.last == nextRun.addingTimeInterval(-1))
    }

    @Test func nextDaySnapshotIsUsed() {
        let nextKey = MRReadinessSnapshot.key(for: at(day: 15, hour: 7), calendar: cal)
        let m = InsightMorning.make(
            runStart: runStart, now: at(day: 15, hour: 8),
            snapshotFor: { $0 == nextKey ? snap(nextKey, level: "rest", line: "오늘은 휴식이나 짧은 이지", at: at(day: 15, hour: 7)) : nil },
            recompute: { _ in readiness(.easy) },
            firstRunStart: { _ in nil },
            actual: nil, direction: nil, calendar: cal)
        #expect(m.nextMorning?.level == "rest")
    }

    @Test func recomputedPendingLineHasNoSyncTail() {
        let m = InsightMorning.make(
            runStart: runStart, now: at(day: 14, hour: 9),
            snapshotFor: { _ in nil },
            recompute: { _ in readiness(.easy, pending: true) },
            firstRunStart: { _ in nil },
            actual: nil, direction: nil, calendar: cal)
        #expect(m.morningOf?.line == "오늘은 이지런")
        #expect(m.morningOf?.line.contains("동기화 전") == false)
        #expect(readiness(.easy, pending: true).line.contains("동기화 전"))   // 홈 줄은 그대로
    }

    @Test func pendingNextDaySnapshotFallsBackToRecompute() {
        let nextKey = MRReadinessSnapshot.key(for: at(day: 15, hour: 7), calendar: cal)
        func run(_ nextPending: Bool) -> InsightMorning {
            InsightMorning.make(
                runStart: runStart, now: at(day: 15, hour: 8),
                snapshotFor: { key in
                    guard key == nextKey else { return nil }
                    let s = snap(nextKey, level: "rest", line: "오늘은 휴식이나 짧은 이지", at: at(day: 15, hour: 6))
                    s.hrvPending = true
                    return s
                },
                recompute: { d in d > at(day: 15, hour: 0) ? readiness(.go, pending: nextPending) : readiness(.easy) },
                firstRunStart: { _ in nil },
                actual: nil, direction: "내일은 쉬어 가세요", calendar: cal)
        }
        #expect(run(false).nextMorning?.level == "go")
        let pending = run(true)
        #expect(pending.nextMorning == nil)
        #expect(pending.nextDirection == "내일은 쉬어 가세요")
    }

    @Test func firstSentenceTrim() {
        #expect(InsightMorning.firstSentence("연속 4일째입니다. 강도를 빼 주세요.") == "연속 4일째입니다.")
        #expect(InsightMorning.firstSentence("거리 5.2km입니다.") == "거리 5.2km입니다.")
        #expect(InsightMorning.firstSentence("昨夜は平常です。強度OKです。") == "昨夜は平常です。")
        #expect(InsightMorning.firstSentence("마침표 없음") == "마침표 없음")
    }

    @Test func verdictStripsTodayPrefix() {
        #expect(InsightMorning.verdict(fromLine: "오늘은 이지런 · 연속 4일") == "이지런 · 연속 4일")
        #expect(InsightMorning.verdict(fromLine: "Today: hard is OK") == "hard is OK")
        #expect(InsightMorning.verdict(fromLine: "今日は強度OK") == "強度OK")
    }
}
