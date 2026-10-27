import Foundation

/// 기간별 결산 공유 묶음(월·연)의 내용 — 리듬·PR·대회·VO2 추세·기간 제목. 판정은 전부 여기서(규칙, 결정적).
/// 있는 것만: 장마다 비면 화면 쪽이 그 장을 뺀다. 목표 진행률·달성률·VO2 절댓값 예측은 넣지 않는다.
struct PeriodRecap {
    enum Span: Equatable {
        case month(year: Int, month: Int)
        case year(Int)
    }

    struct PR: Equatable {
        let label: String
        let duration: TimeInterval
        let date: Date
        /// 이 거리를 처음 달린 기간이면 true(첫 완주), 아니면 기존 최고 기록을 넘은 것
        let isFirst: Bool
    }

    struct Race: Equatable {
        let name: String
        let distanceKm: Double
        let duration: TimeInterval
        let date: Date
    }

    struct VO2Trend {
        let points: [(date: Date, value: Double)]
        var start: Double { points.first?.value ?? 0 }
        var end: Double { points.last?.value ?? 0 }
        var delta: Double { end - start }
    }

    let span: Span
    let start: Date
    let end: Date
    /// 그날 0시 → 그날 달린 km(이 기간 안만)
    let dayKm: [Date: Double]
    let runCount: Int
    let totalKm: Double
    let longestDayStreak: Int
    /// 기간과 겹치는 월요일 시작 주(오늘 이후 주 제외), 시간 순 — 그 주 안 기간 내 러닝 km
    let weekKm: [(monday: Date, km: Double)]
    let longestWeekStreak: Int
    let prs: [PR]
    let races: [Race]
    let vo2: VO2Trend?
    let title: String
    let detail: String

    var isYear: Bool { if case .year = span { return true }; return false }
    var runDays: Int { dayKm.count }
    var weeksRan: Int { weekKm.filter { $0.km > 0 }.count }

    /// 성장 탭 PR과 같은 구간
    static let prBuckets: [(id: String, range: ClosedRange<Double>)] = [
        ("5K", 4700...5500), ("10K", 9500...10500), ("half", 20000...22000), ("full", 41000...43000),
    ]

    static func bucketLabel(_ id: String) -> String {
        let L = AppLanguage.shared
        switch id {
        case "half": return L.s("하프", "Half", ja: "ハーフ")
        case "full": return L.s("풀", "Full", ja: "フル")
        default:     return id
        }
    }

    /// runs = 러닝 전체(기간 밖 포함, PR·최장·지난 기간 비교에 씀). 기간에 러닝이 없으면 nil.
    static func make(span: Span, runs allRuns: [Activity], races: [PersistedRaceMatch],
                     vo2Samples: [(date: Date, value: Double)], useMiles: Bool, now: Date = Date(),
                     cal: Calendar = InsightEngine.weekCalendar) -> PeriodRecap? {
        let runs = allRuns.filter { $0.type == .running }
        let (start, end, prevStart): (Date, Date, Date) = {
            switch span {
            case .month(let y, let m):
                let s = cal.date(from: DateComponents(year: y, month: m, day: 1)) ?? now
                return (s, cal.date(byAdding: .month, value: 1, to: s) ?? now,
                        cal.date(byAdding: .month, value: -1, to: s) ?? now)
            case .year(let y):
                let s = cal.date(from: DateComponents(year: y, month: 1, day: 1)) ?? now
                return (s, cal.date(byAdding: .year, value: 1, to: s) ?? now,
                        cal.date(byAdding: .year, value: -1, to: s) ?? now)
            }
        }()
        let inPeriod = runs.filter { $0.date >= start && $0.date < end }
        guard !inPeriod.isEmpty else { return nil }

        var dayKm: [Date: Double] = [:]
        for r in inPeriod { dayKm[cal.startOfDay(for: r.date), default: 0] += r.distance / 1000 }
        var totalKm = 0.0
        for r in inPeriod { totalKm += r.distance / 1000 }

        // 최장 연속 일
        let days = dayKm.keys.sorted()
        var bestDays = 0, curDays = 0
        var prevDay: Date? = nil
        for d in days {
            if let p = prevDay, cal.date(byAdding: .day, value: 1, to: p) == d { curDays += 1 } else { curDays = 1 }
            bestDays = max(bestDays, curDays)
            prevDay = d
        }

        // 월요일 주 — 기간 시작 주부터 (기간 끝·오늘 중 이른 쪽) 주까지
        func monday(_ d: Date) -> Date {
            cal.dateInterval(of: .weekOfYear, for: d)?.start ?? cal.startOfDay(for: d)
        }
        let lastDay = min(cal.date(byAdding: .second, value: -1, to: end) ?? end, now)
        var weeks: [(monday: Date, km: Double)] = []
        var w = monday(start)
        let lastMonday = monday(lastDay)
        while w <= lastMonday {
            let next = cal.date(byAdding: .day, value: 7, to: w) ?? w
            var km = 0.0
            for r in inPeriod where r.date >= w && r.date < next { km += r.distance / 1000 }
            weeks.append((monday: w, km: km))
            w = next
        }
        var bestWeeks = 0, curWeeks = 0
        for wk in weeks {
            curWeeks = wk.km > 0 ? curWeeks + 1 : 0
            bestWeeks = max(bestWeeks, curWeeks)
        }

        // PR — 기간 끝 시점 기준 그 거리 최고 기록이 이 기간에 나왔을 때
        var prs: [PR] = []
        for b in prBuckets {
            let upToEnd = runs.filter { $0.date < end && b.range.contains($0.distance) }
            guard let best = upToEnd.min(by: { $0.duration < $1.duration }),
                  best.date >= start else { continue }
            let isFirst = !upToEnd.contains { $0.date < start }
            prs.append(PR(label: bucketLabel(b.id), duration: best.duration, date: best.date, isFirst: isFirst))
        }

        // 대회 — 확정된 매칭 중 이 기간
        var byID: [UUID: Activity] = [:]
        for r in inPeriod where byID[r.id] == nil { byID[r.id] = r }
        let raceRows: [Race] = races
            .filter { $0.isConfirmed && !$0.isDismissed }
            .compactMap { m in
                guard let a = byID[m.activityID] else { return nil }
                return Race(name: m.raceName, distanceKm: m.distanceKm, duration: a.duration, date: a.date)
            }
            .sorted { $0.date < $1.date }

        // VO2 — 기간 안 표본 2개 이상, 첫·끝 간격 월 14일·연 60일 이상일 때만(추세만)
        let vo2Pts = vo2Samples.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
        let minSpan: TimeInterval = (isYearSpan(span) ? 60 : 14) * 86400
        let vo2: VO2Trend? = {
            guard vo2Pts.count >= 2, let f = vo2Pts.first, let l = vo2Pts.last,
                  l.date.timeIntervalSince(f.date) >= minSpan else { return nil }
            return VO2Trend(points: vo2Pts)
        }()

        // 기간 제목 — 우선순위: 첫 성취 > 기록 향상 > 거리 확장 > 꾸준함 > 거리 증가 > 거리 감소 > 기본
        let L = AppLanguage.shared
        let isYear = isYearSpan(span)
        let prevName = isYear ? L.s("작년", "last year", ja: "昨年") : L.s("지난달", "last month", ja: "先月")
        var prevKm = 0.0
        for r in runs where r.date >= prevStart && r.date < start { prevKm += r.distance / 1000 }
        func fmt(_ km: Double) -> String {
            useMiles ? String(format: "%.1fmi", km * 0.621371) : String(format: "%.1fkm", km)
        }
        let biggestFirst = prs.last { $0.isFirst }
        let biggestPR = prs.last { !$0.isFirst }
        let longestEver = runs.filter { $0.date < end }.max { $0.distance < $1.distance }
        let hadEarlier = runs.contains { $0.date < start }

        let title: String
        let detail: String
        if let f = biggestFirst, hadEarlier {
            title = L.s("문을 연 러닝", "Breaking Through", ja: "扉を開いたラン")
            detail = L.s("처음으로 \(f.label) 거리를 달렸습니다(\(fmtDuration(f.duration))).",
                         "Ran \(f.label) distance for the first time (\(fmtDuration(f.duration))).",
                         ja: "初めて\(f.label)の距離を走りました（\(fmtDuration(f.duration))）。")
        } else if let p = biggestPR {
            title = L.s("한계를 미는 러닝", "Pushing the Edge", ja: "限界を押し広げるラン")
            detail = L.s("\(p.label) 최고 기록 \(fmtDuration(p.duration))을 세웠습니다.",
                         "Set a \(p.label) best of \(fmtDuration(p.duration)).",
                         ja: "\(p.label)の自己ベスト\(fmtDuration(p.duration))を出しました。")
        } else if let lg = longestEver, lg.date >= start, hadEarlier, lg.distance >= 5000 {
            title = L.s("경계를 넓힌 러닝", "Expanding Boundaries", ja: "境界を広げたラン")
            detail = L.s("가장 긴 러닝 \(fmt(lg.distance / 1000))를 달렸습니다.",
                         "Ran your longest ever: \(fmt(lg.distance / 1000)).",
                         ja: "最長のラン\(fmt(lg.distance / 1000))を走りました。")
        } else if bestWeeks >= 4 {
            title = L.s("쌓이는 러닝", "Stacking Up", ja: "積み重なるラン")
            detail = L.s("\(bestWeeks)주 연속 달렸습니다.", "Ran \(bestWeeks) weeks in a row.",
                         ja: "\(bestWeeks)週連続で走りました。")
        } else if prevKm > 0, totalKm >= prevKm * 1.1 {
            title = L.s("자산 축적 러닝", "Banking Miles", ja: "財産を積み上げるラン")
            detail = L.s("\(prevName)보다 \(fmt(totalKm - prevKm)) 더 달렸습니다.",
                         "Ran \(fmt(totalKm - prevKm)) more than \(prevName).",
                         ja: "\(prevName)より\(fmt(totalKm - prevKm))多く走りました。")
        } else if prevKm > 0, totalKm <= prevKm * 0.7 {
            title = L.s("숨 고르는 러닝", "Catching Your Breath", ja: "息を整えるラン")
            detail = L.s("총 \(fmt(totalKm))로 \(prevName)보다 \(fmt(prevKm - totalKm)) 적습니다.",
                         "\(fmt(totalKm)) in total, \(fmt(prevKm - totalKm)) less than \(prevName).",
                         ja: "合計\(fmt(totalKm))で、\(prevName)より\(fmt(prevKm - totalKm))少ないです。")
        } else {
            title = L.s("쌓이는 러닝", "Stacking Up", ja: "積み重なるラン")
            detail = L.s("\(inPeriod.count)회 달려 총 \(fmt(totalKm))입니다.",
                         "\(inPeriod.count) runs, \(fmt(totalKm)) in total.",
                         ja: "\(inPeriod.count)回走って合計\(fmt(totalKm))です。")
        }

        return PeriodRecap(span: span, start: start, end: end, dayKm: dayKm, runCount: inPeriod.count,
                           totalKm: totalKm, longestDayStreak: bestDays, weekKm: weeks,
                           longestWeekStreak: bestWeeks, prs: prs, races: raceRows, vo2: vo2,
                           title: title, detail: detail)
    }

    private static func isYearSpan(_ s: Span) -> Bool { if case .year = s { return true }; return false }

    static func fmtDuration(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
