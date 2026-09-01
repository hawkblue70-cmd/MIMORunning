import SwiftUI
import Charts

// MARK: - Shared: Long-Distance Context

/// 거리 문맥 판정 — 단일 소스. 폼 탭·리듬 탭 공용.
/// .longRun/.lsd 이거나 현재 거리 > 4주 평균 러닝 × 1.50 또는 절대 거리 ≥ 12km 이면 true.
func isLongDistanceRunContext(
    activity: Activity,
    workoutType: WorkoutType,
    recentAvgDistanceKm: Double?
) -> Bool {
    if workoutType == .longRun || workoutType == .lsd { return true }
    guard let typical = recentAvgDistanceKm, typical > 0 else { return false }
    let distKm = activity.distance / 1000
    return distKm > typical * 1.50 || distKm >= 12.0
}

// MARK: - Run Form Card

struct RunFormCardView: View {
    let activity: Activity
    var splits: [SplitData] = []
    var avgCadence: Int? = nil
    var avgStrideLength: Double? = nil
    var avgGroundContactTime: Double? = nil
    var avgVerticalOscillation: Double? = nil
    var baseline: RunningFormBaseline? = nil
    var workoutType: WorkoutType = .general
    var intervalSegments: [IntervalSegment] = []
    var hrSamples: [(offset: TimeInterval, bpm: Int)] = []
    var typicalDistanceKm: Double? = nil  // 4주 평균 1회 러닝 거리(km). 장거리 문맥 판단에 사용.
    var heatModel: MRHeatModel? = nil
    var formShifts: [MRFormShift] = []
    var hasRecentGap: Bool = false
    var weatherSnapshot: WeatherSnapshot? = nil

    // 버킷 계산은 러닝당 1회만 — onAppear 시 저장, splitFormTrendSection·logTrend에서 재사용
    @State private var formSeriesCache: [FormSeries] = []

    // MARK: - Nested Types

    enum MetricDir { case cadence, stride, groundContact, verticalOsc }
    enum MetricStatus { case inRange, above, below, unknown }
    enum RunningStyle { case quickStep, bigStride, normal, unknown }

    struct FormInsightItem: Identifiable {
        enum Kind: String { case temperature, weather, trend, distance, cadenceHR, style, formChange }
        var id: Kind
        var badgeText: String
        var bodyText: String
        var badgeColor: Color
    }

    struct ChainChild: Identifiable {
        let id: Int
        let label: String
        let rawValue: Double
        let formatted: String
        let unit: String
        let stat: FormStat?
        let dir: MetricDir
        let isRef: Bool
    }

    struct FormSeries {
        struct Point: Identifiable {
            let id: Int         // bucket index
            let kmEnd: Double   // [65] 버킷 끝 누적 km
            let value: Double
            let outOfRange: Bool
        }
        let label: String
        let unit: String
        let points: [Point]
        let bandLo: Double?
        let bandHi: Double?
        let firstAvg: Double?
        let secondAvg: Double?
        let dir: MetricDir
        let lineColor: Color
        let bandIsJudgeable: Bool   // 띠 판정 가능 여부
        let bandSampleCount: Int    // 띠 표본 수 (라벨·로그용)
        let bandPaceMin: Double?    // 띠 기준 페이스 하한 (sec/km) — 라벨용
        let bandPaceMax: Double?    // 띠 기준 페이스 상한 (sec/km) — 라벨용
        let totalSplitCount: Int    // 버킷 전체 수 (결측 표기용)

        var yDomain: ClosedRange<Double> {
            var lo = points.map(\.value).min() ?? 0
            var hi = points.map(\.value).max() ?? 1
            if let b = bandLo { lo = min(lo, b) }
            if let b = bandHi { hi = max(hi, b) }
            // 띠 폭의 25%를 위아래 여백으로 — 띠가 배경이 아닌 "범위"로 읽히도록
            let pad: Double
            if let bLo = bandLo, let bHi = bandHi, bHi > bLo {
                pad = (bHi - bLo) * 0.25
            } else {
                let span = hi - lo
                pad = span > 0 ? span * 0.10 : 1.0
            }
            return (lo - pad)...(hi + pad)
        }
    }

    // MARK: - Computed

    private var bb: BandBaseline? { baseline?.baseline(for: activity) }

    /// 스플릿 차트용 참조 밴드. 페이스가 범위 밖이어도 장거리 문맥에선 가장 느린
    /// 유효 밴드를 참고로 사용 — 띠 배경은 유지하고 OOB 강조만 끈다.
    private var effectiveBb: BandBaseline? {
        if let b = bb { return b }
        guard isLongDistanceContext, let bl = baseline else { return nil }
        for fallback in [PaceBand.verySlow, .jog, .daily, .tempo, .fast] {
            if let found = bl.bands[fallback] { return found }
        }
        return nil
    }

    /// GCT 밴드를 열람 시점 기준으로 보정한 FormStat.
    /// GCT는 지난 1년간 9ms 이상 짧아지는 경우가 있어 현재 밴드로 과거 러닝을 판정하면 오류 발생.
    /// drift = (열람 시점 잔차 3개월 평균) − (baseline 계산 시점 잔차 3개월 평균)
    /// 안전장치: recent 표본 20개 미만(gctShift nil) · R²<0.2 · |drift|<2ms → 보정 없음
    private var adjustedGctStat: FormStat? {
        guard let stat = bb?.groundContact,
              let baselineMean = baseline?.gctBaselineResidualMean else { return bb?.groundContact }
        guard let gctShift = formShifts.first(where: { $0.metric.key == "gct" }) else { return bb?.groundContact }
        if let r2 = gctShift.r2, r2 < 0.2 { return bb?.groundContact }
        let rawDrift = gctShift.recentMean - baselineMean
        guard abs(rawDrift) >= 2 else { return bb?.groundContact }
        let drift = max(-15, min(15, rawDrift))
        return FormStat(median: stat.median + drift, sd: stat.sd, count: stat.count,
                        p10: stat.p10.map { $0 + drift }, p90: stat.p90.map { $0 + drift })
    }

    private var isInterval: Bool { workoutType == .interval }

    /// true → 장거리 문맥. 장거리에서는 지표 하락이 자주 나타남 — 상태 배지를 숨기고 조언을 유보.
    private var isLongDistanceContext: Bool {
        isLongDistanceRunContext(
            activity: activity,
            workoutType: workoutType,
            recentAvgDistanceKm: typicalDistanceKm
        )
    }
    private let lineColor = Color.white.opacity(0.20)
    // [57] 텍스트 열 고정 너비 — 가장 긴 「수직진폭 (참고) N.N cm」+ 들여쓰기를 수용
    //      네 줄 모두 이 값에서 바가 시작 → 축 좌우 끝 픽셀 정렬
    private let barTextColumnWidth: CGFloat = 120

    private var fullSplits: [SplitData] {
        splits.filter { $0.distanceM >= 900 }
    }

    private var showTrendSection: Bool {
        guard !isInterval, fullSplits.count >= 3 else { return false }
        return fullSplits.contains {
            $0.avgCadence != nil || $0.avgStrideLength != nil ||
            $0.avgGroundContactTime != nil || $0.avgVerticalOscillation != nil
        }
    }

    /// 표시 전용 버킷. 판정 계산(전반/후반 비교 등)은 fullSplits를 직접 사용할 것.
    private func bucketedDisplaySplits(_ splits: [SplitData]) -> [SplitData] {
        guard splits.count > 10 else { return splits }
        let step = splits.count > 20 ? 3 : 2

        var buckets: [SplitData] = []
        var i = 0; var idx = 1; let n = splits.count
        while i < n {
            let group = Array(splits[i..<min(i + step, n)])
            func avgD(_ f: (SplitData) -> Double?) -> Double? {
                let v = group.compactMap(f); return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
            }
            func avgI(_ f: (SplitData) -> Int?) -> Int? {
                let v = group.compactMap(f)
                return v.isEmpty ? nil : Int((Double(v.reduce(0, +)) / Double(v.count)).rounded())
            }
            buckets.append(SplitData(
                id: idx,
                distanceM: group.map(\.distanceM).reduce(0, +),
                duration: group.map(\.duration).reduce(0, +),
                avgHeartRate: avgI(\.avgHeartRate),
                avgCadence: avgI(\.avgCadence),
                avgPower: avgI(\.avgPower),
                avgGroundContactTime: avgD(\.avgGroundContactTime),
                avgStrideLength: avgD(\.avgStrideLength),
                avgVerticalOscillation: avgD(\.avgVerticalOscillation)
            ))
            i += step; idx += 1
        }
        // 로그는 logTrend에서 출력 — 여기서 출력하면 렌더당 N회 중복

        return buckets
    }

    private var formSeries: [FormSeries] {
        guard !isInterval else { return [] }
        let L = AppLanguage.shared
        let fs = fullSplits              // 원본: 판정(전반/후반 비교) 전용
        let bs = bucketedDisplaySplits(fs) // 버킷: 차트 포인트 표시 전용
        guard fs.count >= 3 else { return [] }

        // [65] 버킷별 누적 km — x축 km 표기용
        var accumKm = 0.0
        var bucketKm = [Int: Double]()
        for s in bs { accumKm += s.distanceM / 1000.0; bucketKm[s.id] = accumKm }
        let mid = fs.count / 2
        let firstHalf  = Array(fs.prefix(mid))
        let secondHalf = Array(fs.suffix(from: mid))

        func avg(_ vals: [Double?]) -> Double? {
            let v = vals.compactMap { $0 }
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        // 판정가능 → ±1.2SD×factor / 판정불가(표본<minSamples) → P10-P90 관측 범위
        let bbJudgeable   = bb?.isJudgeable ?? true
        let bbSampleCount = bb?.sampleCount ?? 0
        func splitBounds(_ formStat: FormStat?, dir: MetricDir)
            -> (lo: Double, hi: Double)? {
            guard let stat = formStat else { return nil }
            if !bbJudgeable, let p10 = stat.p10, let p90 = stat.p90 {
                return (lo: roundedDisplay(p10, dir: dir),
                        hi: roundedDisplay(p90, dir: dir))
            }
            let factor: Double = dir == .groundContact ? 1.2 : 1.5
            let halfWidth = (stat.upper - stat.lower) / 2.0 * factor
            return (lo: roundedDisplay(stat.median - halfWidth, dir: dir),
                    hi: roundedDisplay(stat.median + halfWidth, dir: dir))
        }
        let isOOB: (Double, FormStat?, MetricDir) -> Bool = { v, stat, dir in
            guard bbJudgeable else { return false }
            guard let b = splitBounds(stat, dir: dir) else { return false }
            let rv = self.roundedDisplay(v, dir: dir)
            return rv < b.lo || rv > b.hi
        }

        var result: [FormSeries] = []

        // Cadence
        let cadPairs: [(Int, Double)] = bs.compactMap { s in s.avgCadence.map { (s.id, Double($0)) } }
        if !cadPairs.isEmpty {
            let stat = bb?.cadence
            let cb = splitBounds(stat, dir: .cadence)
            result.append(FormSeries(
                label: L.s("케이던스", "Cadence"), unit: "spm",
                points: cadPairs.map { km, v in .init(id: km, kmEnd: bucketKm[km] ?? Double(km), value: v, outOfRange: isOOB(v, stat, .cadence)) },
                bandLo: cb?.lo, bandHi: cb?.hi,
                firstAvg:  avg(firstHalf.map  { $0.avgCadence.map(Double.init) }),
                secondAvg: avg(secondHalf.map { $0.avgCadence.map(Double.init) }),
                dir: .cadence, lineColor: Color(hex: "5CE5D5"),
                bandIsJudgeable: bbJudgeable, bandSampleCount: bbSampleCount,
                bandPaceMin: bb?.paceMin, bandPaceMax: bb?.paceMax, totalSplitCount: bs.count
            ))
        }

        // Stride
        let slPairs: [(Int, Double)] = bs.compactMap { s in s.avgStrideLength.map { (s.id, $0) } }
        if !slPairs.isEmpty {
            let stat = bb?.strideLength
            let sb = splitBounds(stat, dir: .stride)
            result.append(FormSeries(
                label: L.s("보폭", "Stride"), unit: "m",
                points: slPairs.map { km, v in .init(id: km, kmEnd: bucketKm[km] ?? Double(km), value: v, outOfRange: isOOB(v, stat, .stride)) },
                bandLo: sb?.lo, bandHi: sb?.hi,
                firstAvg:  avg(firstHalf.map(\.avgStrideLength)),
                secondAvg: avg(secondHalf.map(\.avgStrideLength)),
                dir: .stride, lineColor: Color(hex: "FFA94D"),
                bandIsJudgeable: bbJudgeable, bandSampleCount: bbSampleCount,
                bandPaceMin: bb?.paceMin, bandPaceMax: bb?.paceMax, totalSplitCount: bs.count
            ))
        }

        // GCT — [109] adjustedGctStat로 시점 보정 밴드 적용
        let gctPairs: [(Int, Double)] = bs.compactMap { s in s.avgGroundContactTime.map { (s.id, $0) } }
        if !gctPairs.isEmpty {
            let stat = adjustedGctStat
            let gb = splitBounds(stat, dir: .groundContact)
            result.append(FormSeries(
                label: L.s("지면접촉", "GCT"), unit: "ms",
                points: gctPairs.map { km, v in .init(id: km, kmEnd: bucketKm[km] ?? Double(km), value: v, outOfRange: isOOB(v, stat, .groundContact)) },
                bandLo: gb?.lo, bandHi: gb?.hi,
                firstAvg:  avg(firstHalf.map(\.avgGroundContactTime)),
                secondAvg: avg(secondHalf.map(\.avgGroundContactTime)),
                dir: .groundContact, lineColor: Color(hex: "A78BFA"),
                bandIsJudgeable: bbJudgeable, bandSampleCount: bbSampleCount,
                bandPaceMin: bb?.paceMin, bandPaceMax: bb?.paceMax, totalSplitCount: bs.count
            ))
        }

        // Vertical Oscillation (참고 전용 — 추세 표시, 판정·OOB 강조 없음)
        let voPairs: [(Int, Double)] = bs.compactMap { s in s.avgVerticalOscillation.map { (s.id, $0) } }
        if !voPairs.isEmpty {
            let voBounds = splitBounds(bb?.verticalOsc, dir: .verticalOsc)
            result.append(FormSeries(
                label: L.s("수직진폭", "Vert Osc"), unit: "cm",
                points: voPairs.map { km, v in .init(id: km, kmEnd: bucketKm[km] ?? Double(km), value: v, outOfRange: false) },
                bandLo: voBounds?.lo, bandHi: voBounds?.hi,
                firstAvg: avg(firstHalf.map(\.avgVerticalOscillation)),
                secondAvg: avg(secondHalf.map(\.avgVerticalOscillation)),
                dir: .verticalOsc, lineColor: Color.white.opacity(0.45),
                bandIsJudgeable: false, bandSampleCount: bbSampleCount,
                bandPaceMin: nil, bandPaceMax: nil, totalSplitCount: bs.count
            ))
        }

        // 데이터 포인트 3개 이하는 추이 차트 자체가 무의미 — 제외 (VO 제외: 데이터 없음 칸 유지 필요)
        return result.filter { s in
            let include = s.dir == .verticalOsc || s.points.count > 3
            #if DEBUG
            if !include {
                print("[폼:추이] \(s.label) 데이터 \(s.points.count)/\(fs.count)스플릿 → 3개 이하 제외")
            }
            #endif
            return include
        }
    }

    // MARK: - Style Classification

    /// 주법 판정. 인터벌·장거리 문맥이면 .unknown. r ≤ -0.3 AND n ≥ 20 이 아니면 .unknown.
    private var runningStyleClassification: RunningStyle {
        guard !isInterval, !isLongDistanceContext,
              let bb,
              let r = bb.cadenceStrideR, r <= -0.3,
              bb.sampleCount >= 20,
              let cad = avgCadence,
              let str = avgStrideLength,
              let cadStat = bb.cadence,
              let strStat = bb.strideLength
        else { return .unknown }

        let cadResidual = Double(cad) - cadStat.median
        let strResidual = str - strStat.median

        if let p90 = bb.cadenceResidualP90, let p25 = bb.strideResidualP25,
           cadResidual >= p90 && strResidual <= p25 { return .quickStep }
        if let p10 = bb.cadenceResidualP10, let p75 = bb.strideResidualP75,
           cadResidual <= p10 && strResidual >= p75 { return .bigStride }
        return .normal
    }

    private func styleBadgeInfo(for style: RunningStyle) -> (text: String, color: Color)? {
        let L = AppLanguage.shared
        switch style {
        case .quickStep: return (L.s("잔발형", "Quick Step"), Color(hex: "4ECDC4"))
        case .bigStride: return (L.s("큰보폭형", "Big Stride"), Color(hex: "FFA94D"))
        case .normal:    return (L.s("평소 주법", "Typical"), Color.white.opacity(0.5))
        case .unknown:   return nil
        }
    }

    // MARK: - Insight Slot

    private func paceString(_ secPerKm: Double) -> String {
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d'%02d\"", m, s)
    }

    private func trendInsightText(_ realShifts: [MRFormShift]) -> String {
        let L = AppLanguage.shared
        guard let shift = realShifts.first else { return "" }
        let weeks = shift.weeksConsistent
        let suffix = L.s("\(weeks)주째 ", "for \(weeks) wks ")
        switch shift.metric.key {
        case "vo":
            return shift.delta > 0
                ? L.s("위아래 움직임이 \(suffix)커지고 있어요.", "Vertical oscillation has been \(suffix)increasing.")
                : L.s("위아래 움직임이 \(suffix)줄어들고 있어요.", "Vertical oscillation has been \(suffix)decreasing.")
        case "cadence":
            return shift.delta > 0
                ? L.s("케이던스가 \(suffix)높아지고 있어요.", "Cadence has been \(suffix)increasing.")
                : L.s("케이던스가 \(suffix)낮아지고 있어요.", "Cadence has been \(suffix)decreasing.")
        case "gct":
            return shift.delta > 0
                ? L.s("지면접촉이 \(suffix)길어지고 있어요.", "Ground contact has been \(suffix)increasing.")
                : L.s("지면접촉이 \(suffix)짧아지고 있어요.", "Ground contact has been \(suffix)decreasing.")
        default:
            return L.s("주법 지표에 변화가 있어요.", "A form metric is shifting.")
        }
    }

    private var formInsights: [FormInsightItem] {
        let L = AppLanguage.shared
        var items: [FormInsightItem] = []

        // [96] 장거리 폼 변화 지점 — 거리문맥일 때만, 가장 먼저 삽입 ([97]: 거리문맥에도 표시)
        if let changeItem = longDistanceFormChangeInsight {
            items.append(changeItem)
        }

        // [기온] 야외(temp != nil) AND (temp ≥ 25 OR ≤ 5) AND 모델 유효
        // [날씨] 비 — 기온과 동시에 뜨면 한 슬롯으로 합치고, 기온 없으면 별도 슬롯
        let isRainy = weatherSnapshot?.isRainy == true
        var tempFired = false
        if let temp = activity.temperatureC,
           let model = heatModel, model.ok,
           (temp >= 25 || temp <= 5),
           let pace = activity.paceSecPerKm {
            let corrected = pace * exp(model.logDelta(temp))
            let diff = pace - corrected   // 양수 = 교정 페이스가 빠름
            if diff >= 5 {
                tempFired = true
                let refStr = paceString(corrected)
                let tempStr = String(format: "%.1f", temp)
                let ctx = temp >= 25
                    ? L.s("시원한 날이었다면", "On a cooler day")
                    : L.s("따뜻한 날이었다면", "On a warmer day")
                let text: String
                if isRainy {
                    text = L.s(
                        "\(tempStr)°C에 비까지 왔어요. \(ctx) 같은 노력으로 \(refStr) 정도 나왔을 거예요.",
                        "You ran in \(tempStr)°C rain. \(ctx), same effort might have produced \(refStr).")
                } else {
                    text = L.s(
                        "\(tempStr)°C에서 뛰었어요. \(ctx) 같은 노력으로 \(refStr) 정도 나왔을 거예요.",
                        "You ran at \(tempStr)°C. \(ctx), the same effort might have produced a \(refStr) pace.")
                }
                items.append(FormInsightItem(
                    id: .temperature,
                    badgeText: L.s(isRainy ? "기온·날씨" : "기온", isRainy ? "Temp & Rain" : "Heat"),
                    bodyText: text,
                    badgeColor: Color(hex: "FF8C42")))
            }
        }
        if !tempFired, isRainy, items.count < 3 {
            let text = L.s(
                "비 오는 날이었어요. 노면이 젖으면 지면접촉과 페이스가 평소와 달라질 수 있어요.",
                "It was raining. Wet pavement can affect ground contact and pace.")
            items.append(FormInsightItem(
                id: .weather,
                badgeText: L.s("날씨", "Weather"),
                bodyText: text,
                badgeColor: Color(hex: "6BAED6")))
        }

        // [추세] 공백이 있으면 hasRecentGap=true → mrFormObservation 내에서 nil 반환
        if let obs = mrFormObservation(formShifts, hasRecentGap: hasRecentGap, refCadence: avgCadence), items.count < 3 {
            items.append(FormInsightItem(id: .trend,
                                         badgeText: L.s("추세", "Trend"),
                                         bodyText: obs.text,
                                         badgeColor: Color(hex: "7FD98A")))
        }

        // [거리] distance ≥ 4주 평균 × 130%
        if let typical = typicalDistanceKm, typical > 0,
           (activity.distance / 1000) >= typical * 1.30,
           items.count < 3 {
            let distKm = activity.distance / 1000
            let ratio  = distKm / typical
            let text = L.s(
                "\(String(format: "%.1f", distKm))km는 평소(\(String(format: "%.1f", typical))km)의 \(String(format: "%.1f", ratio))배예요.",
                "\(String(format: "%.1f", distKm)) km is \(String(format: "%.1f", ratio))× your usual \(String(format: "%.1f", typical)) km.")
            items.append(FormInsightItem(id: .distance,
                                         badgeText: L.s("거리", "Distance"),
                                         bodyText: text,
                                         badgeColor: Color(hex: "6BAED6")))
        }

        // [케이던스 U자] 같은 페이스에서 심박 최저 케이던스 추정 (우선순위 4위)
        if let item = cadenceHRInsight, items.count < 3 {
            items.append(item)
        }

        // [주법] 잔발형 또는 큰보폭형
        let style = runningStyleClassification
        if (style == .quickStep || style == .bigStride), items.count < 3,
           let badge = styleBadgeInfo(for: style) {
            let text: String
            switch style {
            case .quickStep:
                text = L.s("평소보다 발걸음이 빠르고 보폭이 짧았어요.", "Cadence was higher and stride shorter than usual.")
            case .bigStride:
                text = L.s("평소보다 보폭이 크고 발걸음이 느렸어요.", "Stride was longer and cadence slower than usual.")
            default:
                text = ""
            }
            items.append(FormInsightItem(id: .style,
                                         badgeText: badge.text,
                                         bodyText: text,
                                         badgeColor: Color(hex: "A78BFA")))
        }

        // 총 4줄 상한: 논리적 줄 수 합산 후 초과하면 낮은 우선순위부터 제거
        while items.map({ $0.bodyText.components(separatedBy: "\n").count }).reduce(0, +) > 4, !items.isEmpty {
            items.removeLast()
        }

        // [107] 후보 0개면 측정값 폴백 — 해석 없이 사실만
        if items.isEmpty {
            let distKm  = activity.distance / 1000
            let distStr = String(format: "%.1f", distKm)
            var text: String
            if let pace = activity.paceSecPerKm, pace > 0 {
                let i = Int(pace.rounded())
                let pStr = "\(i / 60)'\(String(format: "%02d", i % 60))\""
                text = L.s("\(distStr)km를 \(pStr) 페이스로 달렸어요.",
                           "You ran \(distStr) km at \(pStr)/km.")
            } else {
                text = L.s("\(distStr)km를 달렸어요.", "You ran \(distStr) km.")
            }
            // 가장 큰 후반 변화 지표 한 줄 추가 (있으면)
            let all = formSeriesCache.isEmpty ? formSeries : formSeriesCache
            let notableChange: String? = all.compactMap { s -> (MetricDir, Double, Double)? in
                guard let f = s.firstAvg, let sec = s.secondAvg, f > 0 else { return nil }
                return (s.dir, f, sec)
            }.max(by: { abs($0.2 - $0.1) / $0.1 < abs($1.2 - $1.1) / $1.1 }).flatMap { dir, f, sec in
                let diff = sec - f
                let absDiff = abs(diff)
                switch dir {
                case .cadence:
                    guard absDiff >= 2 else { return nil }
                    let d = String(format: "%.0f", absDiff)
                    return diff < 0
                        ? L.s("케이던스가 후반에 \(d)spm 낮아졌어요.", "Cadence was \(d) spm lower in the second half.")
                        : L.s("케이던스가 후반에 \(d)spm 높아졌어요.", "Cadence was \(d) spm higher in the second half.")
                case .groundContact:
                    guard absDiff >= 5 else { return nil }
                    let d = String(format: "%.0f", absDiff)
                    return diff < 0
                        ? L.s("지면접촉이 후반에 \(d)ms 짧아졌어요.", "Ground contact was \(d) ms shorter in the second half.")
                        : L.s("지면접촉이 후반에 \(d)ms 길어졌어요.", "Ground contact was \(d) ms longer in the second half.")
                case .stride:
                    guard absDiff >= 0.03 else { return nil }
                    let d = String(format: "%.2f", absDiff)
                    return diff < 0
                        ? L.s("보폭이 후반에 \(d)m 짧아졌어요.", "Stride was \(d) m shorter in the second half.")
                        : L.s("보폭이 후반에 \(d)m 길어졌어요.", "Stride was \(d) m longer in the second half.")
                case .verticalOsc:
                    guard absDiff >= 0.3 else { return nil }
                    let d = String(format: "%.1f", absDiff)
                    return L.s("수직진폭이 후반에 \(d)cm 변했어요.", "Vertical oscillation changed by \(d) cm.")
                }
            }
            if let change = notableChange { text += " " + change }
            items.append(FormInsightItem(id: .trend,
                                         badgeText: L.s("기록", "Stats"),
                                         bodyText: text,
                                         badgeColor: Color.white.opacity(0.45)))
            #if DEBUG
            print("[인사이트] 표시 0개 → 폴백: \(text)")
            #endif
        }

        return Array(items.prefix(3))
    }

    // MARK: - Long-Distance Form Change Insight [96]

    /// 거리문맥 러닝에서 케이던스·보폭·지면접촉이 평소 범위를 벗어난 첫 버킷을 찾아
    /// 관찰 문구를 생성한다. 세 지표 모두 범위 안이면 nil.
    private var longDistanceFormChangeInsight: FormInsightItem? {
        guard isLongDistanceContext else { return nil }
        let L = AppLanguage.shared
        let all = formSeriesCache.isEmpty ? formSeries : formSeriesCache

        struct BandExit {
            let dir: MetricDir
            let kmStart: Double   // 버킷 시작 km
            let kmEnd: Double     // 버킷 끝 km
        }
        var exits: [BandExit] = []
        // [103] 전체 거리의 40% 이전 이탈은 "처음부터 다른 값" — 변화 판정 제외
        let totalKm = activity.distance / 1000
        let minKmForChange = totalKm * 0.40

        for s in all {
            guard s.dir != .verticalOsc else { continue }
            guard let bandLo = s.bandLo, let bandHi = s.bandHi,
                  !s.points.isEmpty else { continue }
            for (i, pt) in s.points.enumerated() {
                let exited: Bool
                switch s.dir {
                case .cadence, .stride:   exited = pt.value < bandLo
                case .groundContact:       exited = pt.value > bandHi
                case .verticalOsc:         exited = false
                }
                if exited {
                    let start = i > 0 ? s.points[i - 1].kmEnd : 0.0
                    guard start >= minKmForChange else { break }  // [103] 초반 이탈 제외
                    exits.append(BandExit(dir: s.dir, kmStart: start, kmEnd: pt.kmEnd))
                    break
                }
            }
        }

        guard !exits.isEmpty else { return nil }
        let sorted = exits.sorted { $0.kmStart < $1.kmStart }

        // 문구 — 관찰+위치만, 원인 표현 없음 [96 ⚠️]
        let lines: [String] = sorted.enumerated().compactMap { idx, e in
            let km = Int(e.kmStart.rounded())
            switch e.dir {
            case .cadence:
                return idx == 0
                    ? L.s("\(km)km 지점부터 케이던스가 평소 범위 아래로 내려갔어요.",
                          "From \(km) km, cadence dropped below its normal range.")
                    : L.s("케이던스는 \(km)km부터였어요.", "Cadence from \(km) km.")
            case .stride:
                return idx == 0
                    ? L.s("\(km)km 지점부터 보폭이 평소 범위 아래로 내려갔어요.",
                          "From \(km) km, stride length dropped below its normal range.")
                    : L.s("보폭은 \(km)km부터였어요.", "Stride from \(km) km.")
            case .groundContact:
                return idx == 0
                    ? L.s("\(km)km 지점부터 지면접촉이 평소 범위 위로 올라갔어요.",
                          "From \(km) km, ground contact time rose above its normal range.")
                    : L.s("지면접촉은 \(km)km부터였어요.", "Ground contact from \(km) km.")
            case .verticalOsc:
                return nil
            }
        }
        guard !lines.isEmpty else { return nil }

        return FormInsightItem(
            id: .formChange,
            badgeText: L.s("폼 변화", "Form Shift"),
            bodyText: lines.joined(separator: "\n"),
            badgeColor: Color(hex: "A78BFA"))
    }

    // MARK: - Cadence-HR U-Curve Insight

    /// 케이던스–심박 U자 곡선 인사이트. 글로벌 조건 + 퍼액티비티 조건 모두 통과 시 반환.
    private var cadenceHRInsight: FormInsightItem? {
        guard !isInterval,
              let diag = baseline?.cadenceHRDiag,
              diag.isGloballyValid,
              let vertex = diag.vertexResidual,
              let bb = bb,
              let cadStat = bb.cadence,
              let actCad = avgCadence
        else { return nil }

        let optimalCadence = Int((cadStat.median + vertex).rounded())

        // 퍼액티비티 조건
        guard abs(optimalCadence - actCad) >= 2 else { return nil }
        guard optimalCadence >= 160, optimalCadence <= 190 else { return nil }

        let L = AppLanguage.shared
        let direction = optimalCadence > actCad
            ? L.s("조금 높은", "slightly higher")
            : L.s("조금 낮은", "slightly lower")
        let body = L.s(
            "같은 페이스에서 케이던스 \(optimalCadence) 근처일 때 심박이 가장 낮았어요. 지금보다 \(direction) 편이 효율적일 수 있어요.",
            "HR was lowest around a cadence of \(optimalCadence) at the same pace. A \(direction) cadence than now may be more efficient."
        )
        return FormInsightItem(id: .cadenceHR,
                               badgeText: L.s("케이던스", "Cadence"),
                               bodyText: body,
                               badgeColor: Color(hex: "4ECDC4"))
    }

    private var chainChildren: [ChainChild] {
        let L = AppLanguage.shared
        var items: [ChainChild] = []
        var n = 0
        if let sl = avgStrideLength {
            items.append(ChainChild(id: n, label: L.s("보폭", "Stride"),
                rawValue: sl, formatted: String(format: "%.2f", sl), unit: "m",
                stat: bb?.strideLength, dir: .stride, isRef: false)); n += 1
        }
        if let gct = avgGroundContactTime {
            items.append(ChainChild(id: n, label: L.s("지면접촉", "GCT"),
                rawValue: gct, formatted: String(format: "%.0f", gct), unit: "ms",
                stat: adjustedGctStat, dir: .groundContact, isRef: false)); n += 1
        }
        if let vo = avgVerticalOscillation {
            items.append(ChainChild(id: n, label: L.s("수직진폭", "Vert Osc"),
                rawValue: vo, formatted: String(format: "%.1f", vo), unit: "cm",
                stat: bb?.verticalOsc, dir: .verticalOsc, isRef: true))
        }
        return items
    }

    // MARK: - Display Rounding Helpers

    private func roundedDisplay(_ v: Double, dir: MetricDir) -> Double {
        switch dir {
        case .cadence, .groundContact: return v.rounded()
        case .stride:                  return (v * 100).rounded() / 100
        case .verticalOsc:             return (v * 10).rounded() / 10
        }
    }

    private func metricFmt(_ v: Double, dir: MetricDir) -> String {
        switch dir {
        case .cadence:       return String(format: "%.0f", v)
        case .stride:        return String(format: "%.2f", v)
        case .groundContact: return String(format: "%.0f", v)
        case .verticalOsc:   return String(format: "%.1f", v)
        }
    }

    private func metricStatus(rawValue: Double, stat: FormStat?, dir: MetricDir) -> MetricStatus {
        guard let stat else { return .unknown }
        let rv = roundedDisplay(rawValue, dir: dir)
        let lo = roundedDisplay(stat.lower, dir: dir)
        let hi = roundedDisplay(stat.upper, dir: dir)
        if rv >= lo && rv <= hi { return .inRange }
        return rv > hi ? .above : .below
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topSummary
            divider
            if isInterval {
                if intervalSegments.contains(where: { $0.stepLabel == "운동" }) {
                    IntervalFatigueCard(segments: intervalSegments,
                                       hrSamples: hrSamples,
                                       workoutStart: activity.date)
                }
            } else {
                causalChain
                divider
                formInsightSection
                if showTrendSection {
                    splitFormTrendSection
                }
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            formSeriesCache = formSeries  // 버킷 1회 계산 → 이후 재사용
            logDistanceContext()
            logChain()
            logTrend()
            logStyleClassification()
            logInsightSlot()
            logUCurve()
            logRangeBar()
            logLongDistanceChange()
            logGctCorrection()
        }
        .onChange(of: formShifts.count) { _, _ in
            #if DEBUG
            // formShifts는 async 완료 후 설정됨 — onAppear 이후 도착하면 재로그
            logInsightSlot()
            logGctCorrection()
            #endif
        }
    }

    // MARK: - Top Summary

    private var topSummary: some View {
        let km = activity.distance / 1000
        let kmStr = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(kmStr)
                    .font(cardNumFont(40))
                    .tracking(-1.6)
                Text("km")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "8A8F99"))
            }
            .foregroundStyle(Color.white)
            HStack(spacing: 0) {
                KPICell(label: AppLanguage.shared.s("시간", "Time"),
                        value: activity.formattedDuration)
                kpiSep
                KPICell(label: AppLanguage.shared.s("페이스", "Pace"),
                        value: activity.formattedPace ?? "--'--\"")
                if let cad = avgCadence {
                    kpiSep
                    KPICell(label: AppLanguage.shared.s("케이던스", "Cadence"),
                            value: "\(cad)", unit: "spm",
                            color: Color(hex: "5CE5D5"),
                            context: isInterval ? AppLanguage.shared.s("전력 구간", "work segs") : nil)
                }
                if let sl = avgStrideLength {
                    kpiSep
                    KPICell(label: AppLanguage.shared.s("보폭", "Stride"),
                            value: String(format: "%.2f", sl), unit: "m",
                            color: Color.white)
                }
            }
        }
    }

    // MARK: - Causal Chain

    @ViewBuilder
    private var causalChain: some View {
        let L = AppLanguage.shared
        let children = chainChildren
        VStack(alignment: .leading, spacing: 0) {
            if let cad = avgCadence {
                rootNodeView(label: isInterval ? L.s("케이던스 (전력)", "Cadence (work)") : L.s("케이던스", "Cadence"),
                             rawValue: Double(cad), formatted: "\(cad)", unit: "spm",
                             stat: bb?.isJudgeable == true ? bb?.cadence : nil, dir: .cadence)
            }
            ForEach(children) { child in
                connectorView
                childNodeView(child: child)
            }
            // [70] 범위 바 설명: 바 아래, 축 시작 x에 맞춰 들여씀
            if let summary = barSummaryText() {
                Color.clear.frame(height: 5)
                HStack(spacing: 0) {
                    Color.clear.frame(width: barTextColumnWidth + 8)
                    Text(summary)
                        .font(.system(size: 8))
                        .foregroundStyle(Color.white.opacity(0.60))
                        .lineSpacing(2.5)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            if let paceStr = activity.formattedPace {
                resultArrowView
                resultNodeView(label: L.s("페이스", "Pace"), value: paceStr)
            }
            if let sentence = narrative {
                Color.clear.frame(height: 10)
                Text(sentence)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let style = runningStyleClassification
            if style != .unknown, let badge = styleBadgeInfo(for: style) {
                Color.clear.frame(height: 8)
                HStack(spacing: 6) {
                    Text(badge.text)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(badge.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badge.color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    if let cad = avgCadence, let str = avgStrideLength,
                       let cadStat = bb?.cadence, let strStat = bb?.strideLength,
                       bb?.isJudgeable == true {
                        Text("\(cad) spm · \(String(format: "%.2f", str))m  (\(AppLanguage.shared.s("평소", "avg")) \(Int(cadStat.median.rounded())) · \(String(format: "%.2f", strStat.median)))")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.38))
                    }
                }
            }
        }
    }

    // MARK: Chain Node Views

    private func rootNodeView(label: String, rawValue: Double, formatted: String,
                              unit: String, stat: FormStat?, dir: MetricDir) -> some View {
        // [57] 텍스트 열을 barTextColumnWidth로 고정 → 네 줄 바가 같은 x에서 시작
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.50)).lineLimit(1)
                    Text(formatted).font(cardNumFont(22)).foregroundStyle(Color.white).lineLimit(1)
                    Text(unit).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.45)).lineLimit(1)
                }
            }
            .frame(width: barTextColumnWidth, alignment: .leading)
            if !isInterval, let stat {
                rangeBarView(rawValue: rawValue, stat: stat, dir: dir,
                             dotValues: recentDotsForBand(dir: dir),
                             totalSamples: bb?.sampleCount ?? 0,
                             bandName: bb?.band.rawValue ?? "")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func childNodeView(child: ChainChild) -> some View {
        // 바 정렬: 들여쓰기를 내부 sub-HStack에 격리하고 바는 바깥 HStack에 배치
        // → 루트 노드와 동일한 x 위치에 바가 정렬됨
        // [57] 들여쓰기 포함한 텍스트 열을 barTextColumnWidth로 고정
        HStack(alignment: .top, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                Color.clear.frame(width: 14)
                    .overlay {
                        Rectangle().fill(lineColor).frame(width: 0.5).frame(width: 14, alignment: .center)
                    }
                Color.clear.frame(width: 6)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(child.label).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.50)).lineLimit(1)
                        Text(child.formatted)
                            .font(cardNumFont(20))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        Text(child.unit).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.45)).lineLimit(1)
                    }
                }
            }
            .frame(width: barTextColumnWidth, alignment: .leading)
            if !isInterval, let stat = child.stat {
                rangeBarView(rawValue: child.rawValue, stat: stat, dir: child.dir,
                             dotValues: recentDotsForBand(dir: child.dir),
                             totalSamples: bb?.sampleCount ?? 0,
                             bandName: bb?.band.rawValue ?? "")
                    .frame(maxWidth: .infinity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var connectorView: some View {
        HStack(spacing: 0) {
            ZStack {
                Rectangle().fill(lineColor).frame(width: 0.5, height: 14).frame(width: 14, alignment: .center)
                Rectangle().fill(lineColor).frame(width: 8, height: 0.5).frame(width: 14, alignment: .trailing)
            }
            .frame(width: 14, height: 14)
            Spacer()
        }
    }

    private var resultArrowView: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .top) {
                Rectangle().fill(lineColor).frame(width: 0.5, height: 12).frame(width: 14, alignment: .center)
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 8, weight: .thin)).foregroundStyle(lineColor)
                    .frame(width: 14, alignment: .center).padding(.top, 10)
            }
            .frame(width: 14, height: 18)
            Spacer()
        }
    }

    private func resultNodeView(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.50))
            Text(value).font(cardNumFont(26)).foregroundStyle(Theme.violet)
        }
    }

    // MARK: - Range Bar

    /// 범위 바 히스토리 점: baseline.allFormSamples에서 열람 러닝 이전 12개월 · 같은 페이스 구간 · 거리 0.5~2배 필터 후 최신 5개.
    private func recentDotsForBand(dir: MetricDir) -> [Double] {
        guard let baseline = baseline, !baseline.allFormSamples.isEmpty else { return [] }
        guard let actPace = activity.paceSecPerKm else { return [] }
        let actBand = baseline.cutoffs.band(of: actPace)
        let todayDist = activity.distance
        let viewDate = activity.date
        let cal = Calendar.current
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: viewDate) ?? .distantPast
        let filtered = baseline.allFormSamples.filter { s in
            guard s.distanceM > 0, todayDist > 0 else { return false }
            // 자신 제외
            if cal.isDate(s.date, inSameDayAs: viewDate) { return false }
            // 열람 러닝 이전 12개월
            if s.date >= viewDate { return false }
            if s.date < oneYearAgo { return false }
            // 같은 페이스 구간
            guard baseline.cutoffs.band(of: s.paceSecPerKm) == actBand else { return false }
            // 거리 0.5~2배
            let ratio = todayDist / s.distanceM
            return ratio >= 0.5 && ratio <= 2.0
        }
        return filtered.prefix(5).compactMap { s -> Double? in
            switch dir {
            case .cadence:       return s.cadence.map(Double.init)
            case .stride:        return s.strideLength
            case .groundContact: return s.groundContactTime
            case .verticalOsc:   return s.verticalOscillation
            }
        }
    }

    private func rangeBarView(rawValue: Double, stat: FormStat, dir: MetricDir,
                              dotValues: [Double], totalSamples: Int, bandName: String) -> some View {
        let bandLo = roundedDisplay(stat.lower, dir: dir)
        let bandHi = roundedDisplay(stat.upper, dir: dir)
        let rv     = roundedDisplay(rawValue, dir: dir)
        let loStr  = metricFmt(bandLo, dir: dir)
        let hiStr  = metricFmt(bandHi, dir: dir)

        // [87] 축 범위: 평소 범위가 약 75% 차지 (최소 폭 1.3배, 여백 8%)
        //   → 범위 밖 점도 잘리지 않고, 밴드가 넓게 표시됨
        let allVals: [Double] = [bandLo, bandHi, rv] + dotValues
        let rawLo = allVals.min() ?? bandLo
        let rawHi = allVals.max() ?? bandHi
        let bandWidth = max(bandHi - bandLo, 0.001)
        let minSpan = bandWidth * 1.3
        var axisLo: Double
        var axisHi: Double
        if rawHi - rawLo < minSpan {
            let center = (rawLo + rawHi) / 2
            axisLo = center - minSpan / 2
            axisHi = center + minSpan / 2
        } else {
            axisLo = rawLo
            axisHi = rawHi
        }
        let axisSpan = axisHi - axisLo
        axisLo -= axisSpan * 0.08
        axisHi += axisSpan * 0.08

        let green: Color = Color(hex: "7FD98A")
        let neutral: Color = Color.white.opacity(0.70)
        let dotColor: Color = {
            // [76] 범위 안 + 개선 방향 벗어남 = 녹색. 반대 방향만 회색.
            // [79] 거리 문맥은 색에 영향 없음 — 색은 판정이 아니라 "범위 안" 사실 표시
            switch dir {
            case .cadence:
                return rv >= bandLo ? green : neutral
            case .groundContact:
                return rv <= bandHi ? green : neutral
            case .stride, .verticalOsc:
                // .verticalOsc: 중립 = 방향을 따지지 않음. 범위 안이면 녹색, 벗어나면 회색.
                return rv >= bandLo && rv <= bandHi ? green : neutral
            }
        }()
        // [94] 인라인 로그 제거 — 뷰 재렌더마다 반복 출력됨. logRangeBar()에서 onAppear 1회 출력.

        // [61] 줄별 라벨 삭제 — 카드 하단에 barSummaryText()로 통합

        return VStack(alignment: .leading, spacing: 1) {
            // [55] 축 숫자를 Canvas symbols로 평소 범위 끝 x에 정렬
            Canvas { ctx, size in
                let w = size.width
                guard w > 0, bandHi > bandLo, axisHi > axisLo else { return }
                let barL: CGFloat = 4
                let barR: CGFloat = w - 4
                let barW = barR - barL
                let axisRange = axisHi - axisLo
                let barY: CGFloat = 7

                let posX = { (v: Double) -> CGFloat in
                    barL + CGFloat((v - axisLo) / axisRange) * barW
                }
                let bandLoX = posX(bandLo)
                let bandHiX = posX(bandHi)

                // [63] 전체 축: 배경에 가까운 수준 — 눈금판 역할만
                var fullLine = Path()
                fullLine.move(to: CGPoint(x: barL, y: barY))
                fullLine.addLine(to: CGPoint(x: barR, y: barY))
                ctx.stroke(fullLine, with: .color(.white.opacity(0.04)), lineWidth: 0.5)
                for x in [barL, barR] {
                    var cap = Path()
                    cap.move(to: CGPoint(x: x, y: barY - 2.5))
                    cap.addLine(to: CGPoint(x: x, y: barY + 2.5))
                    ctx.stroke(cap, with: .color(.white.opacity(0.07)), lineWidth: 1)
                }

                // [63] 평소 범위: 훨씬 밝고 굵게 — 축과 두 단계 이상 대비
                var bandLine = Path()
                bandLine.move(to: CGPoint(x: bandLoX, y: barY))
                bandLine.addLine(to: CGPoint(x: bandHiX, y: barY))
                ctx.stroke(bandLine, with: .color(.white.opacity(0.55)), lineWidth: 2.5)
                for x in [bandLoX, bandHiX] {
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: barY - 4))
                    tick.addLine(to: CGPoint(x: x, y: barY + 4))
                    ctx.stroke(tick, with: .color(.white.opacity(0.72)), lineWidth: 2.5)
                }

                // [52] 히스토리 점: 같은 y, 가까운 점끼리 가로 흩뿌림
                let todayX = posX(rv)
                var jxs: [CGFloat] = dotValues.map { posX($0) }
                let jThr: CGFloat = 6; let jOfs: CGFloat = 3.5
                for i in 0..<jxs.count {
                    for j in (i+1)..<jxs.count where abs(jxs[j] - jxs[i]) < jThr {
                        let mid = (jxs[i] + jxs[j]) / 2
                        jxs[i] = mid - jOfs; jxs[j] = mid + jOfs
                    }
                }
                for i in 0..<jxs.count where abs(jxs[i] - todayX) < jThr {
                    jxs[i] = todayX + (i % 2 == 0 ? -jOfs : jOfs)
                }
                for hx in jxs {
                    let r: CGFloat = 3.5
                    ctx.stroke(Path(ellipseIn: CGRect(x: hx-r, y: barY-r, width: r*2, height: r*2)),
                               with: .color(.white.opacity(0.60)), lineWidth: 1.2)
                }
                // 오늘 값: 채운 원, 항상 최상단
                let tr: CGFloat = 4.5
                ctx.fill(Path(ellipseIn: CGRect(x: todayX-tr, y: barY-tr, width: tr*2, height: tr*2)),
                         with: .color(dotColor))

                // [55] lo/hi 숫자: 평소 범위 끝 눈금 아래 가운데 정렬
                if let loSym = ctx.resolveSymbol(id: 0) {
                    let cx = min(max(bandLoX, barL + 8), barR - 8)
                    ctx.draw(loSym, at: CGPoint(x: cx, y: barY + 7), anchor: .top)
                }
                if let hiSym = ctx.resolveSymbol(id: 1) {
                    let cx = min(max(bandHiX, barL + 8), barR - 8)
                    ctx.draw(hiSym, at: CGPoint(x: cx, y: barY + 7), anchor: .top)
                }
            } symbols: {
                // [74] 축 숫자: 설명 문구와 동일 크기/밝기
                Text(loStr).font(.system(size: 8)).foregroundStyle(Color.white.opacity(0.60)).tag(0)
                Text(hiStr).font(.system(size: 8)).foregroundStyle(Color.white.opacity(0.60)).tag(1)
            }
            .frame(height: 26)

        }
    }

    // MARK: - Form Insight Section

    @ViewBuilder
    private var formInsightSection: some View {
        let items = formInsights
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.badgeText)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(item.badgeColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(item.badgeColor.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text(item.bodyText)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            divider
        }
    }

    // MARK: - Split Form Trend (2×2 Grid)

    @ViewBuilder
    private var splitFormTrendSection: some View {
        // formSeriesCache가 비면 ImageRenderer(onAppear 미호출) 상황 — 직접 계산 폴백
        let all = formSeriesCache.isEmpty ? formSeries : formSeriesCache
        let cadS  = all.first { $0.dir == .cadence }
        let gctS  = all.first { $0.dir == .groundContact }
        let slS   = all.first { $0.dir == .stride }
        let voS   = all.first { $0.dir == .verticalOsc }

        let hasTopRow    = cadS != nil || gctS != nil
        let hasBottomRow = slS  != nil || voS  != nil

        if hasTopRow || hasBottomRow {
            VStack(alignment: .leading, spacing: 10) {
                // Row 1: 판정 지표
                if hasTopRow {
                    HStack(alignment: .top, spacing: 10) {
                        if let s = cadS {
                            formSeriesCell(s).frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                        if let s = gctS {
                            formSeriesCell(s).frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                // Row 2: 참고 지표
                if hasBottomRow {
                    HStack(alignment: .top, spacing: 10) {
                        if let s = slS {
                            formSeriesCell(s).frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                        if let s = voS {
                            formSeriesCell(s).frame(maxWidth: .infinity)
                        } else {
                            // 진폭 데이터 없음 placeholder — 칸을 숨기면 레이아웃이 깨짐
                            voNoDataCell.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private var voNoDataCell: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(AppLanguage.shared.s("수직진폭", "Vert Osc"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.30))
            Text(AppLanguage.shared.s("데이터 없음", "No data"))
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.20))
                .frame(height: 52, alignment: .center)
        }
    }

    private func formSeriesCell(_ s: FormSeries) -> some View {
        let L = AppLanguage.shared
        // [65] km x축 계산
        let kmEnds = s.points.map(\.kmEnd)
        let lastKm = kmEnds.last ?? 1.0
        let half = s.points.count / 2
        let midKm: Double = {
            if half > 0, half < s.points.count {
                return (s.points[half - 1].kmEnd + s.points[half].kmEnd) / 2.0
            }
            return lastKm / 2.0
        }()
        let showEveryOther = kmEnds.count > 6
        var displayKms: [Double] = showEveryOther
            ? kmEnds.enumerated().compactMap { i, km in i % 2 == 0 ? km : nil }
            : kmEnds
        if showEveryOther, let lastKmVal = kmEnds.last, displayKms.last != lastKmVal {
            displayKms.append(lastKmVal)
            // [68] 직전 라벨과 너무 가까우면 직전 제거 (예: 14 · 15.5 → 15.5만 유지)
            if displayKms.count >= 3 {
                let normalStep = displayKms[displayKms.count - 2] - displayKms[displayKms.count - 3]
                let lastGap   = displayKms[displayKms.count - 1] - displayKms[displayKms.count - 2]
                if normalStep > 0, lastGap < normalStep * 0.65 {
                    displayKms.remove(at: displayKms.count - 2)
                }
            }
        }
        let kmStep = kmEnds.count > 1 ? (kmEnds[1] - kmEnds[0]) : 1.0
        // 마지막 라벨을 실제 총 거리 위치로 교체 — 버킷 끝(예: 4.5km)과 총 거리(예: 5km)가
        // 다르면 "4  5 km"이 겹쳐 보이는 현상 방지
        let totalKm = activity.distance / 1000
        if !displayKms.isEmpty {
            displayKms[displayKms.count - 1] = totalKm
            // 직전 라벨이 총 거리와 너무 가까우면 제거 (겹침 방지)
            if displayKms.count >= 2 {
                let gap = totalKm - displayKms[displayKms.count - 2]
                if gap < kmStep * 0.7 {
                    displayKms.remove(at: displayKms.count - 2)
                }
            }
        }
        let lastDisplayKm = displayKms.last ?? totalKm
        // 위치 0에 "km" 단위 레이블 삽입 — 숫자 레이블에 "km" 붙이지 않아 겹침 원천 차단
        let displayKmsWithUnit = [0.0] + displayKms
        let totalBuckets = s.totalSplitCount
        let dataCount = s.points.count

        return VStack(alignment: .leading, spacing: 4) {
            // [88] 제목 + 수치/추세 한 줄
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(s.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
                if let f = s.firstAvg, let sec = s.secondAvg {
                    let missingRate = Double(totalBuckets - dataCount) / Double(max(1, totalBuckets))
                    if missingRate > 0.50 {
                        Text(L.s("데이터 부족", "Low data"))
                            .font(.system(size: 8))
                            .foregroundStyle(Color.white.opacity(0.28))
                    } else {
                        trendChangeBadge(dir: s.dir, unit: s.unit, firstAvg: f, secondAvg: sec)
                    }
                } else if s.bandLo != nil {
                    let bandLabel: String = {
                        if s.dir == .verticalOsc || isLongDistanceContext {
                            return L.s("평소 범위 (참고)", "Typical (ref)")
                        }
                        if s.bandIsJudgeable, let pLo = s.bandPaceMin, let pHi = s.bandPaceMax {
                            func pf(_ sec: Double) -> String {
                                let i = Int(sec.rounded())
                                return "\(i / 60)'\(String(format: "%02d", i % 60))\""
                            }
                            return L.s("평소 범위 (\(pf(pLo))~\(pf(pHi)) 러닝 \(s.bandSampleCount)회)",
                                       "Typical (\(pf(pLo))–\(pf(pHi)) · \(s.bandSampleCount) runs)")
                        }
                        if s.bandIsJudgeable {
                            return L.s("평소 범위 n=\(s.bandSampleCount)", "Typical n=\(s.bandSampleCount)")
                        }
                        return L.s("참고 범위 n=\(s.bandSampleCount)", "Ref range n=\(s.bandSampleCount)")
                    }()
                    Text(bandLabel)
                        .font(.system(size: 8))
                        .foregroundStyle(Color.white.opacity(0.28))
                }
                Spacer(minLength: 0)
                if dataCount < totalBuckets && totalBuckets > 0 {
                    Text("(\(dataCount)/\(totalBuckets))")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.white.opacity(0.22))
                }
            }

            // Sparkline chart
            Chart {
                // Normal-range band
                if let lo = s.bandLo, let hi = s.bandHi {
                    RectangleMark(
                        xStart: .value("", 0.0),
                        xEnd: .value("", max(lastKm + kmStep * 0.5, totalKm)),
                        yStart: .value("", lo),
                        yEnd: .value("", hi)
                    )
                    .foregroundStyle(Color.white.opacity(0.08))
                }

                // Midpoint divider
                RuleMark(x: .value("", midKm))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                    .foregroundStyle(Color.white.opacity(0.15))

                // Line
                ForEach(s.points) { pt in
                    LineMark(
                        x: .value("km", pt.kmEnd),
                        y: .value("val", pt.value)
                    )
                    .foregroundStyle(s.lineColor)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                }

                // In-range small dots
                ForEach(s.points.filter { !$0.outOfRange }) { pt in
                    PointMark(x: .value("km", pt.kmEnd), y: .value("val", pt.value))
                        .foregroundStyle(s.lineColor.opacity(0.45))
                        .symbolSize(12)
                }

                // Out-of-range: white halo then colored inner (장거리 문맥이면 OOB 강조 생략)
                if !isLongDistanceContext {
                    ForEach(s.points.filter(\.outOfRange)) { pt in
                        PointMark(x: .value("km", pt.kmEnd), y: .value("val", pt.value))
                            .foregroundStyle(Color.white)
                            .symbolSize(64)
                    }
                    ForEach(s.points.filter(\.outOfRange)) { pt in
                        PointMark(x: .value("km", pt.kmEnd), y: .value("val", pt.value))
                            .foregroundStyle(s.lineColor)
                            .symbolSize(32)
                    }
                }
            }
            .chartYScale(domain: s.yDomain)
            .chartXScale(domain: 0...max(lastKm + kmStep * 0.5, totalKm))
            .chartXAxis {
                AxisMarks(values: displayKmsWithUnit) { val in
                    if let v = val.as(Double.self) {
                        let isUnit = v < 0.01   // position 0 → "km" 단위 표시
                        let isLast = !isUnit && abs(v - lastDisplayKm) < 0.01
                        if isUnit {
                            // "km" 단위 레이블: 맨 앞에 한번만, 숫자와 겹침 없음
                            AxisValueLabel(anchor: .topLeading) {
                                Text("km")
                                    .font(.system(size: 7))
                                    .foregroundStyle(Color.white.opacity(0.30))
                            }
                        } else {
                            let fmtKm = v.truncatingRemainder(dividingBy: 1) < 0.05
                                ? String(format: "%.0f", v)
                                : String(format: "%.1f", v)
                            if isLast {
                                AxisValueLabel(anchor: .topTrailing) {
                                    Text(fmtKm)
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.white.opacity(0.55))
                                }
                            } else {
                                AxisValueLabel(centered: false) {
                                    Text(fmtKm)
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.white.opacity(0.55))
                                }
                            }
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 52)

            if isLongDistanceContext, let bandLo = s.bandLo {
                let belowCount = s.points.filter { $0.value < bandLo }.count
                if s.points.count > 0, Double(belowCount) / Double(s.points.count) >= 0.30 {
                    Text(AppLanguage.shared.s("장거리라 평소 범위 아래에 머물러요",
                                              "Long run — staying below normal range is natural"))
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
        }
    }

    private func trendChangeBadge(dir: MetricDir, unit: String, firstAvg: Double, secondAvg: Double) -> some View {
        let diff = secondAvg - firstAvg
        let fmtNum: (Double) -> String = { v in metricFmt(v, dir: dir) }
        let diffUnit = dir == .groundContact ? "ms" : ""
        let sign: String = diff > 0.0005 ? "+" : diff < -0.0005 ? "−" : "±"
        let label = "\(fmtNum(firstAvg)) → \(fmtNum(secondAvg)) (\(sign)\(fmtNum(abs(diff)))\(diffUnit))"
        let green = Color(hex: "7FD98A")
        let muted = Color.white.opacity(0.70)
        let color: Color
        switch dir {
        case .cadence:       color = diff > 0.0005 ? green : muted
        case .groundContact: color = diff < -0.0005 ? green : muted
        default:             color = muted
        }
        return Text(label)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(color)
    }

    // MARK: - Bar Summary

    /// [61] 범위 바 설명 — 카드 하단에 한 줄. 밴드 이름 대신 페이스 범위 사용.
    private func barSummaryText() -> String? {
        let L = AppLanguage.shared
        guard !isInterval, let bb = bb, bb.sampleCount > 0 else { return nil }
        let paceMin = bb.paceMin
        let paceMax = bb.paceMax
        guard paceMin > 0, paceMax > 0 else { return nil }
        func pf(_ sec: Double) -> String {
            let i = Int(sec.rounded())
            return "\(i/60)'\(String(format: "%02d", i%60))\""
        }
        let n = bb.sampleCount
        let pr = "\(pf(paceMin))~\(pf(paceMax))"
        let todayDist = activity.distance
        // [112] allFormSamples 풀에서 재필터 (페이스 구간 + 12개월 창 + 거리)
        let actPaceBS = activity.paceSecPerKm ?? 0
        let actBandBS = baseline?.cutoffs.band(of: actPaceBS)
        let viewDateBS = activity.date
        let oneYearAgoBS = Calendar.current.date(byAdding: .year, value: -1, to: viewDateBS) ?? .distantPast
        let poolBS = baseline?.allFormSamples ?? []
        let recentCount = min(poolBS.filter { s in
            guard s.distanceM > 0, todayDist > 0 else { return false }
            if Calendar.current.isDate(s.date, inSameDayAs: viewDateBS) { return false }
            if s.date >= viewDateBS { return false }
            if s.date < oneYearAgoBS { return false }
            guard baseline?.cutoffs.band(of: s.paceSecPerKm) == actBandBS else { return false }
            let ratio = todayDist / s.distanceM
            return ratio >= 0.5 && ratio <= 2.0
        }.count, 5)
        let line1 = L.s(
            "눈금 사이 = 평소 범위 · \(pr) 러닝 \(n)회",
            "Ticks = typical range · \(n) runs at \(pr)")
        // [93] 0건일 때 "비교할 만한 거리의 러닝이 없어요", 2건 이상만 흰 점 표기
        let dotLine: String
        if recentCount == 0 {
            dotLine = L.s("\n비교할 만한 거리의 러닝이 없어요",
                          "\nNo runs of similar distance to compare")
        } else if recentCount >= 2 {
            dotLine = L.s("\n흰 점 = 거리가 비슷한 최근 \(recentCount)회",
                          "\nWhite dots = \(recentCount) recent similar-distance runs")
        } else {
            dotLine = ""
        }
        let caveat: String = n < 3
            ? L.s("\n비교 대상이 적어 참고용이에요.", "\nLimited samples — treat as reference only.")
            : ""
        return line1 + dotLine + caveat
    }

    // MARK: - Narrative

    private var narrative: String? {
        let L = AppLanguage.shared
        guard let cad = avgCadence else { return nil }
        let cadD = Double(cad)
        let paceStr = activity.formattedPace ?? "--"
        let cadStr  = "\(cad)"
        let slStr   = avgStrideLength.map { String(format: "%.2f", $0) }
        let gctStr  = avgGroundContactTime.map { String(format: "%.0f", $0) }

        if cadD < 160 {
            return L.s("케이던스가 \(cad)spm이에요. 보폭이 큰 편이에요.",
                        "Cadence is \(cad) spm — stride is on the longer side.")
        }
        // 인터벌: 회복 구간이 포함된 전체 평균이라 개인 기준 비교를 생략한다
        if isInterval {
            let base = slStr.map {
                L.s("케이던스 \(cadStr)spm, 보폭 \($0)m로 \(paceStr) 페이스가 나왔어요.",
                     "Cadence \(cadStr) spm and stride \($0) m produced a \(paceStr) pace.")
            } ?? L.s("케이던스 \(cadStr)spm으로 \(paceStr) 페이스가 나왔어요.",
                      "A cadence of \(cadStr) spm produced a \(paceStr) pace.")
            return base + " " + L.s(
                "인터벌은 회복 구간이 섞여 평균만으로는 폼을 판단하기 어려워요.",
                "Mixed with recovery intervals — averages alone don't reflect form."
            )
        }
        guard bb?.isJudgeable == true else {
            return slStr.map { L.s("케이던스 \(cadStr)spm으로 보폭 \($0)m를 만들어 \(paceStr) 페이스가 나왔어요.",
                                   "A cadence of \(cadStr) spm and \($0) m stride produced a \(paceStr) pace.") }
                ?? L.s("케이던스 \(cadStr)spm으로 \(paceStr) 페이스가 나왔어요.",
                        "A cadence of \(cadStr) spm produced a \(paceStr) pace.")
        }

        // 장거리 문맥: 장거리에서는 지표 하락이 자주 나타남 — 판단 유보, 사실 서술만 표시
        if isLongDistanceContext {
            let distKm = activity.distance / 1000
            let typeName = workoutType.koreanLabel  // localized: "거리주" KO / "Distance Run" EN
            let distKmStr = String(format: "%.0f", distKm)
            // 실제로 범위 아래인 지표가 있는지 확인 — 없으면 "평소 범위 그대로" 문구 사용
            let cadSt = metricStatus(rawValue: cadD, stat: bb?.cadence, dir: .cadence)
            let gctSt: MetricStatus = avgGroundContactTime.map {
                metricStatus(rawValue: $0, stat: adjustedGctStat, dir: .groundContact)
            } ?? .unknown
            let slSt: MetricStatus = avgStrideLength.map {
                metricStatus(rawValue: $0, stat: bb?.strideLength, dir: .stride)
            } ?? .unknown
            let anyBelow = [cadSt, gctSt, slSt].contains(.below)
            let allInRange = [cadSt, gctSt, slSt].allSatisfy { $0 == .inRange || $0 == .unknown }
            if allInRange {
                return L.s(
                    "\(distKmStr)km를 뛰면서 폼이 평소 범위 그대로였어요.",
                    "Your form stayed within the usual range throughout \(distKmStr) km.")
            }
            if !anyBelow {
                // .above만 있고 .below 없음 — 사실 서술 (배지 생략)
                if gctSt == .above {
                    return L.s(
                        "\(distKmStr)km를 뛰면서 지면접촉이 평소보다 조금 길었어요.",
                        "Ground contact ran a bit longer than usual in this \(distKmStr) km run.")
                }
                return L.s(
                    "\(distKmStr)km를 뛰면서 폼이 평소 범위 그대로였어요.",
                    "Your form stayed within the usual range throughout \(distKmStr) km.")
            }
            // 사실 서술: 전반/후반 평균으로 실제 변화 표기
            let splitMid = fullSplits.count / 2
            let fHalf = Array(fullSplits.prefix(splitMid))
            let sHalf = Array(fullSplits.suffix(fullSplits.count - splitMid))
            func cadAvg(_ arr: [SplitData]) -> Int? {
                let v = arr.compactMap { $0.avgCadence }
                return v.isEmpty ? nil : Int((Double(v.reduce(0, +)) / Double(v.count)).rounded())
            }
            func slAvg(_ arr: [SplitData]) -> Double? {
                let v = arr.compactMap { $0.avgStrideLength }
                return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
            }
            let fstCad = cadAvg(fHalf); let sndCad = cadAvg(sHalf)
            let fstSL  = slAvg(fHalf);  let sndSL  = slAvg(sHalf)
            var korParts: [String] = []
            var engParts: [String] = []
            if let fc = fstCad, let sc = sndCad {
                korParts.append("케이던스 \(fc)→\(sc)spm")
                engParts.append("cadence \(fc)→\(sc) spm")
            }
            if let fs2 = fstSL, let ss2 = sndSL {
                korParts.append("보폭 \(String(format: "%.2f", fs2))→\(String(format: "%.2f", ss2))m")
                engParts.append("stride \(String(format: "%.2f", fs2))→\(String(format: "%.2f", ss2)) m")
            }
            if !korParts.isEmpty {
                if let typical = typicalDistanceKm, (distKm > typical * 1.50 || distKm >= 12.0),
                   !formInsights.contains(where: { $0.id == .distance }) {
                    let delta = distKm - typical
                    return L.s(
                        "평소보다 \(String(format: "%.1f", delta))km 긴 \(typeName)이에요. \(korParts.joined(separator: ", "))로 줄었어요.",
                        "This \(typeName) is \(String(format: "%.1f", delta)) km longer than usual — \(engParts.joined(separator: ", ")).")
                }
                return L.s(
                    "\(distKmStr)km를 뛰면서 \(korParts.joined(separator: ", "))로 줄었어요.",
                    "\(distKmStr) km run — \(engParts.joined(separator: ", ")).")
            }
            // 스플릿 데이터 없음 — 전체 평균으로 서술
            return slStr.map {
                L.s("케이던스 \(cadStr)spm, 보폭 \($0)m로 \(paceStr) 페이스를 달렸어요.",
                    "Cadence \(cadStr) spm and stride \($0) m for the \(paceStr) pace.")
            } ?? L.s("케이던스 \(cadStr)spm으로 \(paceStr) 페이스를 달렸어요.",
                     "Cadence \(cadStr) spm for the \(paceStr) pace.")
        }

        let cadStatus = metricStatus(rawValue: cadD, stat: bb?.cadence, dir: .cadence)
        let gctStatus: MetricStatus = avgGroundContactTime.map {
            metricStatus(rawValue: $0, stat: adjustedGctStat, dir: .groundContact)
        } ?? .unknown
        let slStatus: MetricStatus = avgStrideLength.map {
            metricStatus(rawValue: $0, stat: bb?.strideLength, dir: .stride)
        } ?? .unknown

        // 보폭 이탈 구절 — 사실 서술(중립). 케이던스·GCT 둘 다 이탈이면 3개 → 보폭 생략
        let cadDeviated = cadStatus != .inRange && cadStatus != .unknown
        let gctDeviated = gctStatus != .inRange && gctStatus != .unknown
        let slDeviated  = slStatus  != .inRange && slStatus  != .unknown
        let strideClause: String?
        if slDeviated, !(cadDeviated && gctDeviated), let sl = slStr {
            strideClause = slStatus == .above
                ? L.s("보폭이 \(sl)m로 평소보다 컸어요.", "Stride was \(sl) m — longer than usual.")
                : L.s("보폭이 \(sl)m로 평소보다 작았어요.", "Stride was \(sl) m — shorter than usual.")
        } else {
            strideClause = nil
        }

        if let g = gctStr {
            if gctStatus == .below {
                if cadStatus == .inRange {
                    let base = L.s("평소 리듬대로 \(cadStr)spm을 유지했고, 지면접촉이 \(g)ms로 짧았어요.",
                                   "Cadence held at your usual \(cadStr) spm, with ground contact short at \(g) ms.")
                    if let sc = strideClause { return base + " " + sc }
                    return base
                }
                return L.s("발걸음이 평소보다 빠르게 돌았어요. 지면접촉이 \(g)ms로 짧았어요.",
                            "Cadence was faster than usual. Ground contact was short at \(g) ms.")
            }
            if gctStatus == .above {
                let base = L.s("지면접촉이 \(g)ms로 평소보다 길었어요.",
                                "Ground contact was \(g) ms — longer than usual.")
                if let sc = strideClause { return base + " " + sc }
                return base
            }
        }
        if cadStatus == .below {
            let sfx = slStr.map { " \($0)m" } ?? ""
            return L.s("발걸음이 평소보다 느렸어요. 보폭\(sfx)으로 페이스를 만들었어요.",
                        "Cadence was below your usual. Stride\(sfx) carried the pace.")
        }
        if cadStatus == .above {
            if slStatus == .inRange {
                return L.s("발걸음이 평소보다 빨랐어요. 보폭은 평소 범위였고요.",
                            "Cadence was above your usual. Stride length was within your typical range.")
            }
            if let sc = strideClause {
                return L.s("발걸음이 평소보다 빨랐어요.", "Cadence was above your usual.") + " " + sc
            }
            return L.s("발걸음이 평소보다 빨랐어요.",
                        "Cadence was above your usual.")
        }
        return slStr.map { L.s("케이던스 \(cadStr)spm, 보폭 \($0)m로 평소와 비슷한 \(paceStr) 페이스가 나왔어요.",
                               "Cadence \(cadStr) spm and stride \($0) m produced the usual \(paceStr) pace.") }
            ?? L.s("케이던스 \(cadStr)spm으로 평소와 비슷하게 \(paceStr) 페이스를 달렸어요.",
                    "A cadence of \(cadStr) spm produced the usual \(paceStr) pace.")
    }

    // MARK: - Log

    private func logDistanceContext() {
        #if DEBUG
        let distKm = activity.distance / 1000
        let typical = typicalDistanceKm
        let typicalStr = typical.map { String(format: "%.1f", $0) } ?? "-"
        let pctStr: String = typical.map { t in t > 0 ? "\(Int(distKm / t * 100 + 0.5))%" : "-" } ?? "-"
        let msg = isLongDistanceContext ? "→ 문맥 적용 (지표 배지·해석 생략)" : "→ 미적용"
        print("[폼:거리문맥] \(String(format: "%.1f", distKm))km / 4주평균 \(typicalStr)km (\(pctStr)) type=\(workoutType.koreanLabel)  \(msg)")
        #endif
    }

    private func logChain() {
        #if DEBUG
        guard !isInterval else { return }
        func pf(_ s: Double) -> String { String(format: "%d'%02d\"", Int(s) / 60, Int(s) % 60) }
        func rng(_ s: FormStat?, _ fmt: String) -> String {
            guard let s else { return "기준없음" }
            return String(format: "\(fmt)–\(fmt)(폭\(fmt))", s.lower, s.upper, s.upper - s.lower)
        }
        let cStr  = avgCadence.map { "\($0)" } ?? "-"
        let slStr = avgStrideLength.map  { String(format: "%.2f", $0) } ?? "-"
        let gctStr = avgGroundContactTime.map { String(format: "%.0f", $0) } ?? "-"
        let voStr  = avgVerticalOscillation.map { String(format: "%.1f", $0) } ?? "-"
        let pace   = activity.paceSecPerKm.map { pf($0) } ?? "--"
        let narrativeStr = narrative ?? "-"  // evaluate first so [폼] observation logs fire before chain log
        let gctAdj = adjustedGctStat
        let gctWasAdjusted = gctAdj?.median != bb?.groundContact?.median
        let gctBandStr = gctWasAdjusted ? "\(rng(gctAdj, "%.0f")) [보정]" : rng(bb?.groundContact, "%.0f")
        let chainLog = "[폼:사슬] C=\(cStr)(\(rng(bb?.cadence, "%.0f"))) 보폭=\(slStr)(\(rng(bb?.strideLength, "%.2f")))"
            + "\n         GCT=\(gctStr)(\(gctBandStr)) VO=\(voStr) 페이스=\(pace)"
            + "\n         → \"\(narrativeStr)\""
        print(chainLog)
        #endif
    }

    private func logTrend() {
        #if DEBUG
        let all = formSeriesCache  // onAppear에서 1회 계산된 캐시 사용
        guard !all.isEmpty else { return }
        let totalBuckets = all[0].totalSplitCount
        print("[폼:추이] \(String(format: "%.1f", activity.distance/1000))km splits=\(fullSplits.count) → 버킷 \(totalBuckets)개")
        for s in all {
            let total   = s.points.count
            let buckets = s.totalSplitCount  // [45] 분모를 전체 버킷 수로 통일
            let oob     = s.points.filter(\.outOfRange).count
            let pct     = total > 0 ? Int(Double(oob) / Double(total) * 100 + 0.5) : 0
            var line1   = "  \(s.label)"
            if let f = s.firstAvg, let sec = s.secondAvg {
                let diff = sec - f
                let sign = diff > 0 ? "+" : ""
                line1 += "  \(metricFmt(f, dir: s.dir))→\(metricFmt(sec, dir: s.dir))(\(sign)\(metricFmt(diff, dir: s.dir)))"
            }
            if let lo = s.bandLo, let hi = s.bandHi {
                let width  = hi - lo
                let method = s.dir == .verticalOsc ? "참고" : (s.bandIsJudgeable ? "평소범위" : "관측범위")
                let nStr   = s.dir == .verticalOsc ? "" : " · n=\(s.bandSampleCount)"
                let jStr   = (s.bandIsJudgeable || s.dir == .verticalOsc) ? "" : " · 판정불가"
                line1 += "  띠(\(method)\(jStr)) \(metricFmt(lo, dir: s.dir))–\(metricFmt(hi, dir: s.dir))(폭\(metricFmt(width, dir: s.dir)))\(nStr)"
            }
            print(line1)
            print("            띠밖 \(oob)/\(total)(\(pct)%) · 데이터 \(total)/\(buckets) 버킷")
        }
        #endif
    }

    private func logGctCorrection() {
        #if DEBUG
        guard let stat = bb?.groundContact else { return }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: activity.date)
        guard let baselineMean = baseline?.gctBaselineResidualMean else {
            print("[폼:GCT보정] baseline 없음 → 보정 안 함")
            return
        }
        guard let gctShift = formShifts.first(where: { $0.metric.key == "gct" }) else {
            print("[폼:GCT보정] 기준일 \(dateStr) · GCT shift 없음 (n부족 또는 미계산) → 보정 안 함")
            return
        }
        let viewingMean = gctShift.recentMean
        let rawDrift = viewingMean - baselineMean
        if let r2 = gctShift.r2, r2 < 0.2 {
            print(String(format: "[폼:GCT보정] 기준일 %@ · R²=%.2f (<0.2) → 보정 안 함", dateStr, r2))
            return
        }
        if abs(rawDrift) < 2 {
            print(String(format: "[폼:GCT보정] 기준일 %@ · drift %+.1fms (<2ms) → 보정 없음", dateStr, rawDrift))
            return
        }
        let drift = max(-15, min(15, rawDrift))
        let lo  = roundedDisplay(stat.lower, dir: .groundContact)
        let hi  = roundedDisplay(stat.upper, dir: .groundContact)
        let aLo = roundedDisplay(stat.lower + drift, dir: .groundContact)
        let aHi = roundedDisplay(stat.upper + drift, dir: .groundContact)
        print(String(format: "[폼:GCT보정] 기준일 %@ · 시점잔차 %+.2f · 기준잔차 %+.2f", dateStr, viewingMean, baselineMean))
        print(String(format: "             drift %+.1fms → 밴드 %.0f–%.0f → %.0f–%.0f", drift, lo, hi, aLo, aHi))
        #endif
    }

    private func logRangeBar() {
        #if DEBUG
        guard let baseline = baseline else { return }
        let pool = baseline.allFormSamples
        guard !pool.isEmpty else {
            print("[폼:범위바] allFormSamples 없음 — 캐시 재계산 후 사용 가능")
            return
        }
        guard let actPace = activity.paceSecPerKm else { return }
        let actBand = baseline.cutoffs.band(of: actPace)
        let todayDist = activity.distance
        let viewDate = activity.date
        let cal = Calendar.current
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: viewDate) ?? .distantPast
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"

        // 1단계: 날짜 창 (자신 제외 + 이전 + 12개월)
        let inWindow = pool.filter { s in
            !cal.isDate(s.date, inSameDayAs: viewDate) &&
            s.date < viewDate &&
            s.date >= oneYearAgo
        }
        // 2단계: 페이스 구간
        let inBand = inWindow.filter { baseline.cutoffs.band(of: $0.paceSecPerKm) == actBand }
        // 3단계: 거리 0.5~2배
        let inDist = inBand.filter { s in
            guard s.distanceM > 0, todayDist > 0 else { return false }
            let ratio = todayDist / s.distanceM
            return ratio >= 0.5 && ratio <= 2.0
        }
        let recent5 = Array(inDist.prefix(5))

        let winStart = inWindow.last.map { df.string(from: $0.date) } ?? "?"
        let winEnd   = df.string(from: viewDate)
        print("[폼:범위바] 후보 풀 = \(winStart) ~ \(winEnd) · 러닝 \(inWindow.count)건")
        print("             구간 통과 \(inBand.count)건 · 거리 통과 \(inDist.count)건 · 표시 \(recent5.count)건")

        if !recent5.isEmpty {
            let dots = recent5.map { s in "\(df.string(from: s.date))(\(String(format:"%.1f", s.distanceM/1000))km)" }
            print("[폼:범위바] 샘플 = \(dots.joined(separator: " · "))")
        }

        // 거리 필터 탈락 상세 (통과 0건일 때)
        if inDist.isEmpty, !inBand.isEmpty {
            let loKm = (todayDist / 2) / 1000
            let hiKm = (todayDist * 2) / 1000
            let rejectExamples = inBand.prefix(5).map { String(format: "%.1f", $0.distanceM / 1000) + "km" }
            print(String(format: "[폼:범위바] 거리 창 = %.1f~%.1fkm · 후보 \(inBand.count)건 → 통과 0건", loKm, hiKm))
            print("             탈락 예시: " + rejectExamples.joined(separator: " · "))
        }
        #endif
    }

    private func logLongDistanceChange() {
        #if DEBUG
        guard isLongDistanceContext else { return }
        let all = formSeriesCache.isEmpty ? formSeries : formSeriesCache

        struct BandExit {
            let dir: MetricDir; let kmStart: Double; let kmEnd: Double; let bucketIdx: Int
        }
        var exits: [BandExit] = []
        let totalKmLog = activity.distance / 1000
        let minKmLog = totalKmLog * 0.40
        for s in all {
            guard s.dir != .verticalOsc else { continue }
            guard let bandLo = s.bandLo, let bandHi = s.bandHi, !s.points.isEmpty else { continue }
            for (i, pt) in s.points.enumerated() {
                let exited: Bool
                switch s.dir {
                case .cadence, .stride: exited = pt.value < bandLo
                case .groundContact: exited = pt.value > bandHi
                case .verticalOsc: exited = false
                }
                if exited {
                    let start = i > 0 ? s.points[i - 1].kmEnd : 0.0
                    if start < minKmLog {
                        // [103] 초반 이탈 로그
                        let dirNames: [MetricDir: String] = [.cadence:"케이던스",.stride:"보폭",.groundContact:"지면접촉",.verticalOsc:"수직진폭"]
                        print("[폼:장거리변화] \(dirNames[s.dir, default: "?"] ) 버킷\(i+1)부터 범위 밖 — 초반 이탈(40% 기준 \(String(format:"%.1f",minKmLog))km 미만)로 판정 제외")
                        break
                    }
                    exits.append(BandExit(dir: s.dir, kmStart: start, kmEnd: pt.kmEnd, bucketIdx: i))
                    break
                }
            }
        }
        if exits.isEmpty {
            print("[폼:장거리변화] 세 지표 모두 범위 안(또는 초반 이탈) — 변화 없음")
            return
        }
        let sorted = exits.sorted { $0.kmStart < $1.kmStart }
        let dname: (MetricDir) -> String = {
            switch $0 {
            case .cadence: return "케이던스"
            case .stride: return "보폭"
            case .groundContact: return "지면접촉"
            case .verticalOsc: return "수직진폭"
            }
        }
        let parts = sorted.map { e in
            "\(dname(e.dir)) = 버킷\(e.bucketIdx + 1)(\(Int(e.kmStart.rounded()))~\(Int(e.kmEnd.rounded()))km)"
        }
        let earliest = sorted.first!
        print("[폼:장거리변화] \(parts.joined(separator: " · ")) → 변화 시작 \(Int(earliest.kmStart.rounded()))km")
        #endif
    }

    private func logInsightSlot() {
        #if DEBUG
        let items = formInsights
        let tempFiredDebug = items.contains { $0.id == .temperature }
        let isRainyDebug = weatherSnapshot?.isRainy == true
        let kinds: [FormInsightItem.Kind] = (tempFiredDebug && isRainyDebug)
            ? [.formChange, .temperature, .trend, .distance, .cadenceHR, .style]
            : [.formChange, .temperature, .weather, .trend, .distance, .cadenceHR, .style]
        let candidates: [(FormInsightItem.Kind, String)] = kinds
            .map { kind in
                let found = items.first { $0.id == kind }
                let label: String
                switch kind {
                case .temperature:
                    if let t = activity.temperatureC {
                        let suffix = (isRainyDebug && tempFiredDebug) ? " · 비 (날씨 통합)" : ""
                        label = "\(String(format: "%.1f", t))°C\(suffix)"
                    } else { label = "temp nil" }
                case .weather:
                    label = weatherSnapshot?.isRainy == true ? "비 있음" : "비 없음"
                case .trend:
                    let n = formShifts.filter(\.isReal).count
                    if let obs = mrFormObservation(formShifts, hasRecentGap: hasRecentGap, refCadence: avgCadence) {
                        label = obs.isStable ? "안정(\(formShifts.count)개)" : "실증 \(n)/\(formShifts.count)"
                    } else {
                        label = hasRecentGap ? "공백→침묵" : "실증 \(n)/\(formShifts.count)"
                    }
                case .distance:
                    let km = activity.distance / 1000
                    let typ = typicalDistanceKm.map { String(format: "%.1f", $0) } ?? "-"
                    label = "\(String(format: "%.1f", km))km / 4주평균 \(typ)km"
                case .cadenceHR:
                    if let diag = baseline?.cadenceHRDiag, diag.isGloballyValid,
                       let vertex = diag.vertexResidual,
                       let cadStat = bb?.cadence {
                        let opt = Int((cadStat.median + vertex).rounded())
                        label = "최적케이던스 \(opt) (현재 \(avgCadence.map { "\($0)" } ?? "-"))"
                    } else {
                        label = "글로벌 조건 미충족"
                    }
                case .style:
                    switch runningStyleClassification {
                    case .quickStep: label = "잔발형"
                    case .bigStride: label = "큰보폭형"
                    case .normal:    label = "평소 주법"
                    case .unknown:   label = "생략"
                    }
                case .formChange:
                    label = longDistanceFormChangeInsight != nil ? "변화 있음" : "변화 없음"
                }
                let mark = found != nil ? "✓" : "✗"
                return (kind, "\(mark) \(kind.rawValue)  \(label)")
            }
        print("[인사이트] 후보 \(kinds.count)개 검토")
        candidates.forEach { print("  \($0.1)") }
        if items.isEmpty {
            print("[인사이트] 표시 없음")
        } else {
            print("[인사이트] 표시 \(items.count)개: \(items.map(\.id.rawValue).joined(separator: ", "))")
        }
        #endif
    }

    private func logUCurve() {
        #if DEBUG
        guard let diag = baseline?.cadenceHRDiag else {
            print("[U자] 진단 없음 (HR 데이터 부족 또는 baseline 미계산)")
            return
        }
        let rangeOK = diag.residualRangeP10P90 >= 10
        let binsOK  = diag.binCount >= 5
        var line1 = "[U자] 잔차범위 \(String(format: "%.1f", diag.residualRangeP10P90))spm(\(rangeOK ? "✓" : "<10 ✗")) bin=\(diag.binCount)(\(binsOK ? "✓" : "<5 ✗"))"
        var reasons: [String] = []
        if !rangeOK { reasons.append("잔차범위 부족") }
        if !binsOK  { reasons.append("bin 부족") }

        if let a = diag.a, let r2 = diag.r2 {
            let aOK  = a > 0
            let r2OK = r2 >= 0.3
            line1 += " a=\(String(format: "%+.2f", a))(\(aOK ? "✓" : "✗")) R²=\(String(format: "%.2f", r2))(\(r2OK ? "✓" : "<0.3 ✗"))"
            if !aOK  { reasons.append("아래로 볼록 아님") }
            if !r2OK { reasons.append("R² 부족") }
        }
        print(line1)

        if let vertex = diag.vertexResidual,
           let cadStat = bb?.cadence {
            let optCad = Int((cadStat.median + vertex).rounded())
            print("      최저점 \(String(format: "%+.1f", vertex))spm → 최적 케이던스 \(optCad)")
            if let actCad = avgCadence {
                if abs(optCad - actCad) < 2 { reasons.append("현재 케이던스와 차이 <2spm") }
                if optCad < 160 || optCad > 190 { reasons.append("절대 범위 밖 (\(optCad)spm)") }
            }
            print("      → \(reasons.isEmpty ? "표시" : "미표시: \(reasons.joined(separator: ", "))")")
        } else {
            if reasons.isEmpty { reasons.append("최저점 범위 밖 또는 회귀 실패") }
            print("      → 미표시: \(reasons.joined(separator: ", "))")
        }
        #endif
    }

    private func logStyleClassification() {
        #if DEBUG
        guard let bb else { return }
        let bandName = bb.band.rawValue
        guard let r = bb.cadenceStrideR else {
            print("[주법] 판정 생략 — \(bandName) 상관계수 없음")
            return
        }
        if isLongDistanceContext {
            print("[주법] 판정 생략 — 장거리 문맥 (\(bandName) r=\(String(format: "%+.3f", r)))")
            return
        }
        if isInterval {
            print("[주법] 판정 생략 — 인터벌")
            return
        }
        if r > -0.3 {
            print("[주법] 판정 생략 — \(bandName) r=\(String(format: "%+.3f", r)) (음의 상관 아님)")
            return
        }
        if bb.sampleCount < 20 {
            print("[주법] 판정 생략 — \(bandName) n=\(bb.sampleCount) < 20")
            return
        }
        print("[주법] 구간=\(bandName) r=\(String(format: "%.3f", r)) n=\(bb.sampleCount) → 판정 수행")
        guard let cad = avgCadence, let str = avgStrideLength,
              let cadStat = bb.cadence, let strStat = bb.strideLength else { return }
        let cadR = Double(cad) - cadStat.median
        let strR = str - strStat.median
        let p90c = bb.cadenceResidualP90.map { String(format: "P90=%+.1f", $0) } ?? "P90=?"
        let p25s = bb.strideResidualP25.map  { String(format: "P25=%+.3f", $0) } ?? "P25=?"
        let p10c = bb.cadenceResidualP10.map { String(format: "P10=%+.1f", $0) } ?? "P10=?"
        let p75s = bb.strideResidualP75.map  { String(format: "P75=%+.3f", $0) } ?? "P75=?"
        let cadCkQS = bb.cadenceResidualP90.map { cadR >= $0 ? "✓" : "✗" } ?? "?"
        let strCkQS = bb.strideResidualP25.map  { strR <= $0 ? "✓" : "✗" } ?? "?"
        let cadCkBS = bb.cadenceResidualP10.map { cadR <= $0 ? "✓" : "✗" } ?? "?"
        let strCkBS = bb.strideResidualP75.map  { strR >= $0 ? "✓" : "✗" } ?? "?"
        let styleStr: String
        switch runningStyleClassification {
        case .quickStep: styleStr = "잔발형"
        case .bigStride: styleStr = "큰보폭형"
        case .normal:    styleStr = "평소 주법"
        case .unknown:   styleStr = "알 수 없음"
        }
        print("      잔발형 체크: 케이던스 잔차 \(String(format: "%+.1f", cadR)) (\(p90c) \(cadCkQS)) 보폭 잔차 \(String(format: "%+.3f", strR)) (\(p25s) \(strCkQS))")
        print("      큰보폭형 체크: 케이던스 잔차 \(String(format: "%+.1f", cadR)) (\(p10c) \(cadCkBS)) 보폭 잔차 \(String(format: "%+.3f", strR)) (\(p75s) \(strCkBS))")
        print("      → \(styleStr)")
        #endif
    }

    // MARK: - Helpers

    private var kpiSep: some View {
        Rectangle().fill(Color.white.opacity(0.10)).frame(width: 0.5, height: 40)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
    }

    @ViewBuilder
    private func placeholderSection(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.25))
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }
}
