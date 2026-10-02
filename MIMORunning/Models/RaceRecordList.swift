import Foundation

/// 나 탭 참가 대회 — 예정 | 기록.
enum RaceListMode: Equatable {
    case planned
    case records
}

/// 나 탭 참가 대회 · 기록 모드의 행을 만드는 순수 로직.
///
/// SwiftData·HealthKit·SwiftUI에 의존하지 않는다 — 뷰가 확정 매칭·러닝·아카이브·엔진 예측을
/// 아래 입력 구조체로 평평하게 바꿔 넘긴다.
///
/// 규칙(설계 `2026-09-27-my-races-entry-design.md`):
///  · 같은 날짜는 한 행. 확정 대회 러닝 > 러닝 없는 훈련 계획 아카이브.
///  · 엔진 예측만 있고 확정 러닝이 없는 날(대회급 훈련 러닝)은 목록에 없다.
///  · 예측 줄은 같은 날·같은 표준 거리(±2%)의 엔진 예측이 있을 때만.
///  · 예측 값은 항상 엔진 예측(대회 전날까지 데이터로 다시 계산한 값) — 구간 안/밖·정확도·각주와 같은 기준.
///    아카이브의 계획 시작 시점 예측은 쓰지 않는다(아카이브는 계획 버튼·삭제용 위치만).
enum RaceRecordList {

    /// 확정된 대회 러닝 하나.
    struct RunInput {
        let activityID: UUID
        let raceName: String
        /// 공식 종목 거리(km) — 확정 매칭에 저장된 값
        let distanceKm: Double
        /// 러닝 시작 시각
        let date: Date
        let durationSec: TimeInterval
    }

    /// 훈련 계획 아카이브 하나. `index`는 뷰가 가진 아카이브 배열에서의 위치 — 시트·삭제에서 원본을 찾을 때 쓴다.
    struct ArchiveInput {
        let index: Int
        let raceName: String
        let raceDate: Date
        let distanceM: Double
        let hasResult: Bool
        let actualMin: Double
        /// 주차별 이행표가 있는가(`mrArchiveHasDetail`)
        let hasDetail: Bool
    }

    /// 엔진 예측 행(백테스트) 중 예측이 있는 것.
    struct PredictionInput {
        let date: Date
        /// 표준 거리(km) — 5 · 10 · 21.0975 · 42.195
        let distanceKm: Double
        let predictedMin: Double
        let errorPct: Double
        let inBand: Bool
        /// 같은 대회를 워치 VO2max 환산표(Daniels)로 예측했을 때의 오차(%). 대회 전 60일 내 VO2max가 없으면 nil.
        var vo2ErrorPct: Double? = nil
        /// 같은 대회의 워치 VO2max 환산표 예측(분). 대회 줄에 "VO2max 환산표 3:28:02"로 보인다.
        var vo2PredictedMin: Double? = nil
    }

    struct Prediction: Equatable {
        let predictedMin: Double
        let inBand: Bool
        var vo2PredictedMin: Double? = nil
    }

    struct Row: Identifiable, Equatable {
        enum Source: Equatable {
            case run(activityID: UUID)
            case archiveOnly
        }
        let id: String
        let date: Date
        /// 표시 이름(`RaceDisplayName.short`)
        let name: String
        let distanceLabel: String
        /// 완주 시간(분). nil = 기록 없음
        let finishMin: Double?
        let source: Source
        let prediction: Prediction?
        /// 같은 시리즈 N회째 — 2 이상일 때만
        let editionCount: Int?
        /// 이 날짜의 훈련 계획 아카이브 위치 — 삭제·계획 시트용
        let archiveIndex: Int?
        /// 계획 버튼을 보이는가(아카이브에 주차별 이행표가 있음)
        let hasPlan: Bool

        var opensRun: Bool {
            if case .run = source { return true }
            return false
        }
    }

    struct Accuracy: Equatable {
        let hit: Int
        let count: Int
        let meanAbsErrorPct: Double
        /// 워치 VO2max 환산표 비교 — 두 예측이 모두 있는 대회가 2건 이상일 때만
        var vo2: VO2Comparison? = nil
    }

    /// 워치 VO2max 환산표(가민·블로그식)와 앱 예측을 **같은 대회 묶음**에서 비교한 값.
    /// 앱이 질 때도 그대로 보여 준다 — 맞은 것만 고르면 광고다(2026-10-02).
    struct VO2Comparison: Equatable {
        let count: Int
        let appMeanAbsErrorPct: Double
        let vo2MeanAbsErrorPct: Double
        /// 모든 대회에서 환산표 예측이 실제보다 빨랐는가 / 느렸는가
        let allFaster: Bool
        let allSlower: Bool
    }

    // MARK: - 행

    static func rows(runs: [RunInput],
                     archives: [ArchiveInput] = [],
                     predictions: [PredictionInput] = [],
                     seriesKey: ((RunInput) -> String?)? = nil,
                     calendar: Calendar = .current) -> [Row] {
        func day(_ d: Date) -> Date { calendar.startOfDay(for: d) }

        let dedupRuns = dedupedRuns(runs, calendar: calendar)

        var out: [Row] = []
        var runDays = Set<Date>()

        for r in dedupRuns {
            let d = day(r.date)
            runDays.insert(d)
            let dayArchives = archives.filter { day($0.raceDate) == d }
            // 계획 버튼·삭제용 아카이브 — 같은 거리(±2%) 우선, 없으면 그날 첫 아카이브
            let arch = dayArchives.first {
                abs(($0.distanceM / 1000) - r.distanceKm) / max(r.distanceKm, 0.001) <= 0.02
            } ?? dayArchives.first
            let prediction = prediction(for: r, in: predictions, calendar: calendar).map { p in
                Prediction(predictedMin: p.predictedMin, inBand: p.inBand, vo2PredictedMin: p.vo2PredictedMin)
            }
            var edition: Int? = nil
            if let seriesKey, let key = seriesKey(r) {
                let n = dedupRuns.filter { seriesKey($0) == key && day($0.date) <= d }.count
                if n >= 2 { edition = n }
            }
            out.append(Row(
                id: r.activityID.uuidString,
                date: r.date,
                name: RaceDisplayName.short(r.raceName),
                distanceLabel: RaceDisplayName.distanceLabel(km: r.distanceKm),
                finishMin: r.durationSec / 60,
                source: .run(activityID: r.activityID),
                prediction: prediction,
                editionCount: edition,
                archiveIndex: arch?.index,
                hasPlan: arch?.hasDetail ?? false))
        }

        // 러닝이 없는 날의 아카이브 — 하루에 여럿이면 하나만: 결과 있음 > 이행표 있음 > 입력 순서상 먼저.
        var archiveOnlyByDay: [Date: ArchiveInput] = [:]
        var archiveOnlyDayOrder: [Date] = []
        for a in archives {
            let d = day(a.raceDate)
            guard !runDays.contains(d) else { continue }
            if let existing = archiveOnlyByDay[d] {
                if preferArchive(a, over: existing) { archiveOnlyByDay[d] = a }
            } else {
                archiveOnlyByDay[d] = a
                archiveOnlyDayOrder.append(d)
            }
        }
        for d in archiveOnlyDayOrder {
            let a = archiveOnlyByDay[d]!
            out.append(Row(
                id: "archive-\(Int(a.raceDate.timeIntervalSince1970))-\(Int(a.distanceM))",
                date: a.raceDate,
                name: RaceDisplayName.short(a.raceName),
                distanceLabel: RaceDisplayName.distanceLabel(km: a.distanceM / 1000),
                finishMin: (a.hasResult && a.actualMin > 0) ? a.actualMin : nil,
                source: .archiveOnly,
                prediction: nil,
                editionCount: nil,
                archiveIndex: a.index,
                hasPlan: a.hasDetail))
        }

        return out.sorted { $0.date > $1.date }
    }

    // MARK: - 예측 정확도

    /// 확정 대회 러닝과 짝지어진 엔진 예측만 집계한다. 짝이 하나도 없으면 nil.
    static func accuracy(runs: [RunInput],
                         predictions: [PredictionInput],
                         calendar: Calendar = .current) -> Accuracy? {
        let dedupRuns = dedupedRuns(runs, calendar: calendar)
        let matched = dedupRuns.compactMap { prediction(for: $0, in: predictions, calendar: calendar) }
        guard !matched.isEmpty else { return nil }
        let meanAbs = matched.map { abs($0.errorPct) }.reduce(0, +) / Double(matched.count)
        return Accuracy(hit: matched.filter(\.inBand).count, count: matched.count, meanAbsErrorPct: meanAbs,
                        vo2: vo2Comparison(matched))
    }

    /// 1건으로는 우연과 구분할 수 없어 2건부터.
    private static func vo2Comparison(_ matched: [PredictionInput]) -> VO2Comparison? {
        let pairs = matched.compactMap { p in p.vo2ErrorPct.map { (app: p.errorPct, vo2: $0) } }
        guard pairs.count >= 2 else { return nil }
        let n = Double(pairs.count)
        return VO2Comparison(count: pairs.count,
                             appMeanAbsErrorPct: pairs.map { abs($0.app) }.reduce(0, +) / n,
                             vo2MeanAbsErrorPct: pairs.map { abs($0.vo2) }.reduce(0, +) / n,
                             allFaster: pairs.allSatisfy { $0.vo2 < 0 },
                             allSlower: pairs.allSatisfy { $0.vo2 > 0 })
    }

    /// 정확도 상자의 환산표 항목(개조식 — 사용자 요청으로 '~입니다' 없이, 2026-10-02). 비교가 없으면 nil.
    /// 환산표 비교 대회가 정확도 줄과 같은 묶음이 아니면 그 대회들의 앱 오차를 함께 밝힌다.
    static func vo2Sentence(_ acc: Accuracy, english: Bool) -> String? {
        guard let v = acc.vo2 else { return nil }
        let vo2 = String(format: "%.1f", v.vo2MeanAbsErrorPct)
        let app = String(format: "%.1f", v.appMeanAbsErrorPct)
        var s: String
        if v.count == acc.count {
            s = english ? "VO2max table: avg error \(vo2)%"
                        : "VO2max 환산표: 평균 오차 \(vo2)%"
        } else {
            s = english ? "VO2max table (\(v.count) races with VO2max): avg error \(vo2)% · this app \(app)% on the same races"
                        : "VO2max 환산표(VO2max 있는 \(v.count)건): 평균 오차 \(vo2)% · 같은 \(v.count)건 앱 \(app)%"
        }
        if v.allFaster {
            s += english ? " · all \(v.count) faster than actual" : " · \(v.count)건 모두 실제보다 빠름"
        } else if v.allSlower {
            s += english ? " · all \(v.count) slower than actual" : " · \(v.count)건 모두 실제보다 느림"
        }
        return s
    }

    // MARK: - 토글 기본값

    /// 오늘 이후(오늘 포함) 예정 대회가 하나라도 있으면 예정, 없으면 기록. 날짜를 읽지 못한 예정 대회는 앞으로 있는 것으로 본다.
    static func defaultMode(plannedDates: [Date?], today: Date,
                            calendar: Calendar = .current) -> RaceListMode {
        let start = calendar.startOfDay(for: today)
        return plannedDates.contains { ($0 ?? .distantFuture) >= start } ? .planned : .records
    }

    // MARK: - 내부

    /// 같은 날짜에 확정 러닝이 여럿이면 하나만 남긴다 — 가장 오래 뛴 것, 동률이면 입력 순서상 먼저.
    private static func dedupedRuns(_ runs: [RunInput], calendar: Calendar) -> [RunInput] {
        var byDay: [Date: RunInput] = [:]
        var dayOrder: [Date] = []
        for r in runs {
            let d = calendar.startOfDay(for: r.date)
            if let existing = byDay[d] {
                if r.durationSec > existing.durationSec { byDay[d] = r }
            } else {
                byDay[d] = r
                dayOrder.append(d)
            }
        }
        return dayOrder.map { byDay[$0]! }
    }

    /// 러닝 없는 같은 날 아카이브가 여럿일 때 우선순위: 결과 있음 > 이행표 있음 > 동률이면 기존(입력 순서상 먼저) 유지.
    private static func preferArchive(_ candidate: ArchiveInput, over existing: ArchiveInput) -> Bool {
        let candidateHasResult = candidate.hasResult && candidate.actualMin > 0
        let existingHasResult = existing.hasResult && existing.actualMin > 0
        if candidateHasResult != existingHasResult { return candidateHasResult }
        if candidate.hasDetail != existing.hasDetail { return candidate.hasDetail }
        return false
    }

    /// 같은 날·같은 표준 거리(±2%)의 엔진 예측.
    private static func prediction(for run: RunInput, in predictions: [PredictionInput],
                                   calendar: Calendar) -> PredictionInput? {
        predictions.first {
            calendar.isDate($0.date, inSameDayAs: run.date)
            && abs($0.distanceKm - run.distanceKm) / max($0.distanceKm, 0.001) <= 0.02
        }
    }
}
