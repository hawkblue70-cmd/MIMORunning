import Foundation

// MARK: - 템포 구간 효율 — 같은 페이스 km의 심박 추세 (1단계: 진단 로그만, 화면 없음)
//
// 설계: docs/research/2026-11-03-literature-and-suggestions.md 2.3절
//
// 근거: 2023 체계적 문헌고찰(Int J Sports Med 44(2):95–107) — 표준화된 최대하 속도의 심박 변화는 유산소 체력 변화와
//   대체로 큰 상관(r 0.51–0.88), 90% HRmax 쪽 속도가 70%보다 상관이 크다 → 이지런보다 템포 구간을 본다.
// 앱 적용(문헌 = 틀, 본인 데이터 = 값):
//   · 띠 = 본인 역치 페이스 +5~+25초/km(하프~마라톤 노력). ⚠ 폭 20초는 임의로 정함.
//   · km 3~10만 — 1·2km는 워밍업, 10km 뒤는 심박 드리프트. ⚠ 경계는 임의로 정함.
//   · 러닝마다 띠 안 km 2개↑의 심박 중앙값, 본인 기온-심박 모델로 15°C 기준. 인터벌은 회복이 섞인 km라 제외.
// 화면에서 말할 때는 판정어 없이 사실("같은 페이스에서 심박 N bpm")만 — 안정시 심박 카드와 같은 원칙.

enum MRTempoEfficiency {
    static let bandLoSec = 5.0
    static let bandHiSec = 25.0
    static let firstKm = 3
    static let lastKm = 10
    static let minKmPerRun = 2
    /// 평소 페이스 띠 반폭(초/km) ⚠ 임의로 정함 — 템포 띠만으론 월 1~2회라(2026-11-03 실기기) 표본 확보용
    static let usualHalfWidthSec = 10.0
    /// 효율 비교에서 빼는 유형 — 인터벌(회복이 섞인 km)·대회(범위에 드는 km는 후반에 지쳐 느려진 km, 실기기 10/4 169bpm)
    static let excludedTypes: Set<WorkoutType> = [.interval, .race]
    /// 추세에 쓰는 달의 최소 러닝 수 ⚠ 임의로 정함 — 실기기 5월 4회(9km)만 튀었다(2026-11-03)
    static let minRunsPerMonth = 5

    struct KmRow: Equatable {
        let km: Int
        let paceSec: Double
        let hr: Double
    }

    struct RunRow: Equatable {
        let date: Date
        let type: WorkoutType?
        let tempC: Double?
        let kms: [KmRow]
    }

    struct RunValue: Equatable {
        let date: Date
        /// 15°C 기준 심박(띠 안 km 중앙값)
        let hr: Double
        let rawHR: Double
        let paceSec: Double
        let kmCount: Int
    }

    struct Month: Equatable {
        let monthStart: Date
        let runs: Int
        let kmCount: Int
        /// 러닝별 값의 중앙값(15°C 기준)
        let hr: Double
        let paceSec: Double
    }

    /// 온전한 km(990m↑)·심박 있음·km 3~10.
    static func kmRows(splits: [SplitData]) -> [KmRow] {
        splits.compactMap { s in
            guard s.distanceM >= 990, s.duration > 0, let hr = s.avgHeartRate, hr > 0,
                  (firstKm...lastKm).contains(s.id) else { return nil }
            return KmRow(km: s.id, paceSec: s.duration / (s.distanceM / 1000), hr: Double(hr))
        }
    }

    static func tempoBand(thresholdPace: Double) -> ClosedRange<Double> {
        (thresholdPace + bandLoSec)...(thresholdPace + bandHiSec)
    }

    /// 평소 페이스 띠 — 비교 대상 러닝(인터벌·대회 제외)의 km 페이스 중앙값 ±10초. km가 없으면 nil.
    static func usualBand(_ runs: [RunRow]) -> ClosedRange<Double>? {
        let paces = runs.filter { !isExcluded($0) }.flatMap { $0.kms.map(\.paceSec) }
        guard !paces.isEmpty else { return nil }
        let m = mrMedian(paces)
        return (m - usualHalfWidthSec)...(m + usualHalfWidthSec)
    }

    static func isExcluded(_ r: RunRow) -> Bool { r.type.map { excludedTypes.contains($0) } ?? false }

    static func runValue(_ r: RunRow, thresholdPace: Double, heat: MRHeatHRModel) -> RunValue? {
        runValue(r, band: tempoBand(thresholdPace: thresholdPace), heat: heat)
    }

    /// `bpmPerMetersPerMin`(본인 심박-페이스 회귀 기울기, `MRHRPaceModel.bSpeed`)가 있으면 띠 가운데 페이스로 환산한다 —
    /// 띠(20초) 안에서도 느리게 뛴 달은 심박이 낮게 나온다(실기기 10월 6'21" vs 다른 달 6'15").
    static func runValue(_ r: RunRow, band: ClosedRange<Double>, heat: MRHeatHRModel,
                         bpmPerMetersPerMin: Double? = nil) -> RunValue? {
        guard !isExcluded(r) else { return nil }
        let inBand = r.kms.filter { band.contains($0.paceSec) }
        guard inBand.count >= minKmPerRun else { return nil }
        let raw = mrMedian(inBand.map(\.hr))
        let pace = mrMedian(inBand.map(\.paceSec))
        let center = (band.lowerBound + band.upperBound) / 2
        let paceAdj = bpmPerMetersPerMin.map { $0 * (60_000 / center - 60_000 / pace) } ?? 0
        return RunValue(date: r.date, hr: heat.toRef(raw, tempC: r.tempC) + paceAdj, rawHR: raw,
                        paceSec: pace, kmCount: inBand.count)
    }

    static func monthly(_ runs: [RunRow], thresholdPace: Double, heat: MRHeatHRModel,
                        calendar cal: Calendar = .current) -> [Month] {
        monthly(runs, band: tempoBand(thresholdPace: thresholdPace), heat: heat, calendar: cal)
    }

    /// 성장 탭 '같은 페이스 심박' 카드 값 — 평소 페이스 띠 · 주별 점(2번↑ 뛴 주) + 최근 4주 중앙값 선(4주에 5번↑).
    /// 월 단위는 한 달에 한 번만 바뀌어 주 단위로 바꿨다(2026-11-10 사용자 B안). 주별 점만으로는 러닝 1~2번이라 ±5bpm 잡음이
    /// 2bpm 변화를 덮으므로, 숫자·판정 대신 4주 선을 굵게 그리고 점은 옅게.
    struct Week: Equatable {
        let weekStart: Date
        let runs: Int
        let hr: Double
    }

    struct UsualTrend: Equatable {
        let band: ClosedRange<Double>
        /// 환산 기준 페이스(띠 가운데)
        let centerPace: Double
        /// 주별 중앙값 — 2번 이상 뛴 주만
        let weeks: [Week]
        /// 그 주까지 최근 4주 중앙값 — 4주에 5번 이상일 때만
        let rolling: [Week]
        var first: Week { rolling[0] }
        var latest: Week { rolling[rolling.count - 1] }
    }

    static let minRunsPerWeekPoint = 2
    static let rollingWeeks = 4
    static let minRunsPerRolling = 5
    /// 4주 선 점이 이만큼(약 두 달) 쌓여야 카드를 보인다
    static let minRollingPoints = 8

    static func usualTrend(_ runs: [RunRow], heat: MRHeatHRModel, bpmPerMetersPerMin: Double?,
                           calendar: Calendar = .current) -> UsualTrend? {
        guard let band = usualBand(runs) else { return nil }
        let values = runs.compactMap { runValue($0, band: band, heat: heat, bpmPerMetersPerMin: bpmPerMetersPerMin) }
        guard !values.isEmpty else { return nil }
        // 주 = 월요일 시작(성장 탭·홈 이번 주와 같음)
        var cal = calendar
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        func weekStart(_ d: Date) -> Date { cal.dateInterval(of: .weekOfYear, for: d)?.start ?? cal.startOfDay(for: d) }
        let groups = Dictionary(grouping: values) { weekStart($0.date) }
        let weeks = groups.keys.sorted().compactMap { k -> Week? in
            let g = groups[k]!
            return g.count >= minRunsPerWeekPoint ? Week(weekStart: k, runs: g.count, hr: mrMedian(g.map(\.hr))) : nil
        }
        guard let firstWeek = groups.keys.min(), let lastWeek = groups.keys.max() else { return nil }
        var rolling: [Week] = []
        var w = firstWeek
        while w <= lastWeek {
            guard let from = cal.date(byAdding: .weekOfYear, value: -(rollingWeeks - 1), to: w),
                  let to = cal.date(byAdding: .weekOfYear, value: 1, to: w) else { break }
            let inWindow = values.filter { $0.date >= from && $0.date < to }
            if inWindow.count >= minRunsPerRolling {
                rolling.append(Week(weekStart: w, runs: inWindow.count, hr: mrMedian(inWindow.map(\.hr))))
            }
            guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: w) else { break }
            w = next
        }
        guard rolling.count >= minRollingPoints else { return nil }
        return UsualTrend(band: band, centerPace: (band.lowerBound + band.upperBound) / 2, weeks: weeks, rolling: rolling)
    }

    /// 화면용 추세 — 월 5회 이상인 달만.
    static func trend(_ runs: [RunRow], band: ClosedRange<Double>, heat: MRHeatHRModel,
                      bpmPerMetersPerMin: Double?, calendar cal: Calendar = .current) -> [Month] {
        monthly(runs, band: band, heat: heat, bpmPerMetersPerMin: bpmPerMetersPerMin, calendar: cal)
            .filter { $0.runs >= minRunsPerMonth }
    }

    static func monthly(_ runs: [RunRow], band: ClosedRange<Double>, heat: MRHeatHRModel,
                        bpmPerMetersPerMin: Double? = nil, calendar cal: Calendar = .current) -> [Month] {
        let values = runs.compactMap { runValue($0, band: band, heat: heat, bpmPerMetersPerMin: bpmPerMetersPerMin) }
        let groups = Dictionary(grouping: values) { cal.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        return groups.keys.sorted().map { k in
            let g = groups[k]!
            return Month(monthStart: k, runs: g.count, kmCount: g.map(\.kmCount).reduce(0, +),
                         hr: mrMedian(g.map(\.hr)), paceSec: mrMedian(g.map(\.paceSec)))
        }
    }
}

#if DEBUG
/// 진단 로그 — 역치 페이스·기온 모델(엔진 스토어)과 km 기록(HealthKitManager)이 모두 오면 한 번 찍는다.
@MainActor enum MRTempoEfficiencyDiag {
    static var thresholdPace: Double? { didSet { log() } }
    static var heat: MRHeatHRModel? { didSet { log() } }
    /// 본인 심박-페이스 기울기(bpm per m/min) — 엔진 `hrPace.bSpeed`, 모델 불가면 nil(보정 없이)
    static var paceSlope: Double?
    static var rows: [MRTempoEfficiency.RunRow]? { didSet { log() } }
    private static var logged = false

    private static func log() {
        guard !logged, let t = thresholdPace, let h = heat, let rows else { return }
        logged = true
        let lo = mrFormatPace(t + MRTempoEfficiency.bandLoSec), hi = mrFormatPace(t + MRTempoEfficiency.bandHiSec)
        let kmTotal = rows.map(\.kms.count).reduce(0, +)
        print("[템포효율] 역치 \(mrFormatPace(t)) → 띠 \(lo)~\(hi) · 러닝 \(rows.count)건(km3~10 심박 있는 km \(kmTotal)) · 기온 보정 \(h.ok ? String(format: "%.2fbpm/°C%@", h.bpmPerC, h.isFallback ? "(문헌)" : "") : "없음")")
        section("템포효율", band: MRTempoEfficiency.tempoBand(thresholdPace: t), rows: rows, heat: h, listRuns: true)
        if let u = MRTempoEfficiency.usualBand(rows) {
            print("[평소효율] 평소 페이스 띠 \(mrFormatPace(u.lowerBound))~\(mrFormatPace(u.upperBound))(본인 km 페이스 중앙값 ±\(Int(MRTempoEfficiency.usualHalfWidthSec))초, 인터벌·대회 제외)")
            section("평소효율", band: u, rows: rows, heat: h, listRuns: false)
            if let k = paceSlope {
                print("[평소효율:보정] 페이스 보정 \(String(format: "%.2f", k))bpm/(m/min) → 띠 가운데 \(mrFormatPace((u.lowerBound + u.upperBound) / 2)) 기준 · 월 \(MRTempoEfficiency.minRunsPerMonth)회↑만")
                let mf = DateFormatter(); mf.dateFormat = "yy.MM"
                let t = MRTempoEfficiency.trend(rows, band: u, heat: h, bpmPerMetersPerMin: k)
                print("[평소효율:보정] " + (t.isEmpty ? "월 5회 이상인 달 없음" : t.map {
                    "\(mf.string(from: $0.monthStart)) \($0.runs)회·\(mrFormatPace($0.paceSec))·\(Int($0.hr.rounded()))bpm"
                }.joined(separator: " / ")))
            } else {
                print("[평소효율:보정] 심박-페이스 모델 없음 — 페이스 보정 생략")
            }
        }
    }

    private static func section(_ tag: String, band: ClosedRange<Double>, rows: [MRTempoEfficiency.RunRow],
                                heat h: MRHeatHRModel, listRuns: Bool) {
        let df = DateFormatter(); df.dateFormat = "M/d"
        if listRuns {
            for v in rows.compactMap({ MRTempoEfficiency.runValue($0, band: band, heat: h) }) {
                let type = rows.first { $0.date == v.date }?.type?.koreanLabel ?? "?"
                print("[\(tag):러닝] \(df.string(from: v.date)) \(type) · km \(v.kmCount)개 \(mrFormatPace(v.paceSec)) · 심박 \(Int(v.rawHR.rounded())) → 15°C \(Int(v.hr.rounded()))")
            }
        }
        let mf = DateFormatter(); mf.dateFormat = "yy.MM"
        let months = MRTempoEfficiency.monthly(rows, band: band, heat: h)
        let line = months.map { "\(mf.string(from: $0.monthStart)) \($0.runs)회·\($0.kmCount)km·\(mrFormatPace($0.paceSec))·\(Int($0.hr.rounded()))bpm" }
            .joined(separator: " / ")
        print("[\(tag):월] \(line.isEmpty ? "띠 안 러닝 없음" : line)")
        if let f = months.first, let l = months.last, months.count >= 2 {
            print("[\(tag):월] 처음→마지막 \(String(format: "%+.0f", l.hr - f.hr))bpm (판정 없음, 표본 확인용)")
        }
    }
}
#endif
