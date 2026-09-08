import Foundation

/// 기록 카드의 가로축 단위.
enum RecordPeriod {
    case day, week, month
}

/// 한 버킷(하루 / 한 주 / 한 달)의 집계. 러닝이 없는 버킷도 0값으로 존재한다.
struct RecordBar: Identifiable, Equatable {
    let id: Date            // 버킷 시작 (일 00:00 / 월요일 00:00 / 1일 00:00)
    let end: Date           // 버킷 끝 (미포함)
    let km: Double
    let minutes: Double
    let au: Double          // Σ 강도 × 시간(분), 강도 있는 러닝만
    let paceSec: Double?    // 거리 가중 평균 페이스(총 시간 ÷ 총 거리). 페이스 있는 러닝이 없으면 nil
    let meanEffort: Double? // 강도 있는 러닝의 평균 강도. 없으면 nil
    let avgHR: Double?      // 심박 있는 러닝의 시간 가중 평균 심박(bpm). 없으면 nil
    let runCount: Int
    let ratedCount: Int
}

/// 거리·시간·부하·페이스를 하나의 x축(버킷) 위에 올리기 위한 순수 집계기.
/// 화면·차트에 의존하지 않으며 전부 테스트된다.
enum RecordSeries {

    // MARK: - 버킷 경계

    /// 주는 항상 월요일 시작 (calendar.firstWeekday와 무관).
    static func bucketStart(_ date: Date, period: RecordPeriod, calendar: Calendar) -> Date {
        switch period {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            let day = calendar.startOfDay(for: date)
            let weekday = calendar.component(.weekday, from: day)   // 1=일 … 7=토
            let back = (weekday + 5) % 7                            // 월요일까지 되돌릴 일수
            return calendar.date(byAdding: .day, value: -back, to: day) ?? day
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
        }
    }

    private static func advance(_ date: Date, period: RecordPeriod, calendar: Calendar) -> Date {
        switch period {
        case .day:   return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .week:  return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .month: return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        }
    }

    // MARK: - 집계

    /// 창 [start, end)를 period 단위 버킷으로 나눠 집계. 러닝이 없는 버킷도 0값으로 포함한다.
    static func bars(activities: [Activity],
                     effortOf: (UUID) -> Int?,
                     start: Date,
                     end: Date,
                     period: RecordPeriod,
                     calendar: Calendar = .current) -> [RecordBar] {
        guard start < end else { return [] }

        // 1) 버킷 경계 생성
        var starts: [Date] = []
        var cursor = bucketStart(start, period: period, calendar: calendar)
        var guardCount = 0
        while cursor < end && guardCount < 2000 {
            starts.append(cursor)
            let next = advance(cursor, period: period, calendar: calendar)
            guard next > cursor else { break }
            cursor = next
            guardCount += 1
        }
        guard !starts.isEmpty else { return [] }

        // 2) 누산기
        struct Acc {
            var km = 0.0
            var minutes = 0.0
            var au = 0.0
            var paceWeighted = 0.0   // Σ (페이스 × km)
            var pacedKm = 0.0
            var effortSum = 0.0
            var hrWeighted = 0.0     // Σ (심박 × 분)
            var hrMinutes = 0.0
            var runCount = 0
            var ratedCount = 0
        }
        var accs = [Date: Acc](minimumCapacity: starts.count)
        let indexed = Set(starts)

        for a in activities {
            guard a.date >= start, a.date < end else { continue }
            let key = bucketStart(a.date, period: period, calendar: calendar)
            guard indexed.contains(key) else { continue }
            var acc = accs[key] ?? Acc()
            let km = a.distance / 1000
            let minutes = a.duration / 60
            acc.km += km
            acc.minutes += minutes
            acc.runCount += 1
            if let pace = a.paceSecPerKm, pace > 0, km > 0 {
                acc.paceWeighted += pace * km
                acc.pacedKm += km
            }
            if let hr = a.avgHeartRate, hr > 0, minutes > 0 {
                acc.hrWeighted += Double(hr) * minutes
                acc.hrMinutes += minutes
            }
            if let e = effortOf(a.id) {
                let clamped = EffortResolver.clamp(e)
                acc.au += EffortLoad.sessionAU(effort: clamped, durationMin: minutes)
                acc.effortSum += Double(clamped)
                acc.ratedCount += 1
            }
            accs[key] = acc
        }

        // 3) 버킷 배열
        return starts.map { s in
            let acc = accs[s] ?? Acc()
            return RecordBar(
                id: s,
                end: advance(s, period: period, calendar: calendar),
                km: acc.km,
                minutes: acc.minutes,
                au: acc.au,
                paceSec: acc.pacedKm > 0 ? acc.paceWeighted / acc.pacedKm : nil,
                meanEffort: acc.ratedCount > 0 ? acc.effortSum / Double(acc.ratedCount) : nil,
                avgHR: acc.hrMinutes > 0 ? acc.hrWeighted / acc.hrMinutes : nil,
                runCount: acc.runCount,
                ratedCount: acc.ratedCount
            )
        }
    }

    // MARK: - 페이스 0선

    /// 페이스 모드의 0선 — 창 안 거리 가중 평균 페이스(sec/km). 페이스 있는 러닝이 없으면 nil.
    static func paceBaseline(_ bars: [RecordBar]) -> Double? {
        var weighted = 0.0
        var km = 0.0
        for b in bars {
            guard let p = b.paceSec, b.km > 0 else { continue }
            weighted += p * b.km
            km += b.km
        }
        return km > 0 ? weighted / km : nil
    }

    // MARK: - 선 정규화 (최근 12개월 개인 범위)

    /// 선 정규화 범위 — 최근 12개월 개인 범위(같은 period 단위 버킷의 min~max). 값이 2개 미만이면 nil.
    struct MetricRanges: Equatable {
        let pace: ClosedRange<Double>?   // sec/km
        let au: ClosedRange<Double>?
        let hr: ClosedRange<Double>?

        static let empty = MetricRanges(pace: nil, au: nil, hr: nil)
    }

    /// asOf가 속한 버킷까지의 최근 12개월을 같은 period 단위로 나눠 각 지표의 개인 범위를 낸다.
    /// (day → 365일 / week → 52주 / month → 12개월). 데이터가 있는 버킷이 2개 미만인 지표는 nil.
    static func ranges(activities: [Activity],
                       effortOf: (UUID) -> Int?,
                       period: RecordPeriod,
                       asOf: Date,
                       calendar: Calendar = .current) -> MetricRanges {
        let last = bucketStart(asOf, period: period, calendar: calendar)
        let end = advance(last, period: period, calendar: calendar)
        let start: Date
        switch period {
        case .day:   start = calendar.date(byAdding: .day, value: -365, to: end) ?? end
        case .week:  start = calendar.date(byAdding: .day, value: -364, to: end) ?? end
        case .month: start = calendar.date(byAdding: .month, value: -12, to: end) ?? end
        }
        let window = bars(activities: activities, effortOf: effortOf,
                          start: start, end: end, period: period, calendar: calendar)
        return MetricRanges(
            pace: span(window.compactMap(\.paceSec)),
            au: span(window.map(\.au).filter { $0 > 0 }),
            hr: span(window.compactMap(\.avgHR))
        )
    }

    /// 값이 2개 미만이면 nil (선을 정규화할 기준이 못 된다).
    private static func span(_ values: [Double]) -> ClosedRange<Double>? {
        guard values.count >= 2, let lo = values.min(), let hi = values.max() else { return nil }
        return lo...hi
    }

    /// 0...1 정규화. 페이스는 뒤집어(작을수록 1). 범위 폭 0이면 0.5. 창 값이 범위를 벗어나면 0/1로 클램프.
    static func normalized(_ value: Double, in range: ClosedRange<Double>, inverted: Bool = false) -> Double {
        let width = range.upperBound - range.lowerBound
        guard width > 0 else { return 0.5 }
        let t = min(1, max(0, (value - range.lowerBound) / width))
        return inverted ? 1 - t : t
    }

    // MARK: - 요약

    struct Summary: Equatable {
        let totalKm: Double
        let totalMinutes: Double
        let totalAU: Double
        let runCount: Int
        let ratedCount: Int
        let meanPaceSec: Double?
        let bestPaceSec: Double?
        let meanHR: Double?
    }

    /// 심박 있는 버킷의 시간 가중 평균(가중치 = 그 버킷의 총 러닝 분).
    private static func meanHR(_ bars: [RecordBar]) -> Double? {
        var weighted = 0.0
        var minutes = 0.0
        for b in bars {
            guard let hr = b.avgHR, b.minutes > 0 else { continue }
            weighted += hr * b.minutes
            minutes += b.minutes
        }
        return minutes > 0 ? weighted / minutes : nil
    }

    static func summary(_ bars: [RecordBar]) -> Summary {
        Summary(
            totalKm: bars.reduce(0) { $0 + $1.km },
            totalMinutes: bars.reduce(0) { $0 + $1.minutes },
            totalAU: bars.reduce(0) { $0 + $1.au },
            runCount: bars.reduce(0) { $0 + $1.runCount },
            ratedCount: bars.reduce(0) { $0 + $1.ratedCount },
            meanPaceSec: paceBaseline(bars),
            bestPaceSec: bars.compactMap(\.paceSec).min(),
            meanHR: meanHR(bars)
        )
    }
}
