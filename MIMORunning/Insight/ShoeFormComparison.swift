import Foundation

/// 신발별 폼·심박 효율 비교(2026-10-08 사용자 요청).
///
/// 비교 기준은 **러닝 종류 × 거리 구간** — 페이스 구간은 이지런을 따로 뛰지 않는 러너에게 표본이 없다.
/// 같은 종류·비슷한 거리끼리 묶으면 대회화(빠른 날)와 쿠션화(느린 날)가 섞여 페이스 차이가 신발 차이로 보이는 일을 줄인다.
/// 표본이 적어도 숨기지 않는다 — 누적되는 만큼 보여 주고, 횟수를 같이 적어 읽는 사람이 무게를 정하게 한다.
enum ShoeFormComparison {

    /// 거리 구간 — 5km 미만 · 5~10 · 10~15 · 15~21 · 21km 이상
    enum DistanceBucket: Int, CaseIterable, Comparable {
        case under5, from5, from10, from15, from21
        static func of(_ meters: Double) -> DistanceBucket {
            switch meters / 1000 {
            case ..<5:  return .under5
            case ..<10: return .from5
            case ..<15: return .from10
            case ..<21: return .from15
            default:    return .from21
            }
        }
        var label: String {
            switch self {
            case .under5: return "~5km"
            case .from5:  return "5~10km"
            case .from10: return "10~15km"
            case .from15: return "15~21km"
            case .from21: return "21km~"
            }
        }
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    struct Group: Hashable {
        let type: WorkoutType
        let bucket: DistanceBucket
        var label: String { "\(type.koreanLabel) · \(bucket.label)" }
    }

    /// 러닝 하나 — 신발·묶음이 붙은 폼 입력
    struct Run {
        let date: Date
        let distanceM: Double
        let paceSecPerKm: Double
        let avgHeartRate: Int?
        let cadence: Int?
        let stride: Double?
        let contact: Double?
        let oscillation: Double?
        let shoeID: String
        let group: Group

        /// 심박 효율 — 심박 1회에 가는 거리(m). 속도(m/분) ÷ 평균 심박. 높을수록 덜 힘들게 같은 거리를 간다.
        var efficiency: Double? {
            guard let hr = avgHeartRate, hr > 0, paceSecPerKm > 0 else { return nil }
            return (60_000 / paceSecPerKm) / Double(hr)
        }
    }

    enum Metric: CaseIterable {
        case efficiency, contact, oscillation, cadence, stride
        /// 좋은 쪽 — 효율·케이던스는 높게, 지면접촉·수직진폭은 낮게, 보폭은 방향 없음
        var higherIsBetter: Bool? {
            switch self {
            case .efficiency, .cadence: return true
            case .contact, .oscillation: return false
            case .stride: return nil
            }
        }
        func value(_ r: Run) -> Double? {
            switch self {
            case .efficiency:  return r.efficiency
            case .contact:     return r.contact
            case .oscillation: return r.oscillation
            case .cadence:     return r.cadence.map(Double.init)
            case .stride:      return r.stride
            }
        }
        /// 차이를 말할 문턱 — 하루 사이 자연 변동보다 큰 차이로 정함(통제 연구 없음)
        var noticeable: Double {
            switch self {
            case .efficiency:  return 0.03   // 심박당 3cm ≈ 2.5%
            case .contact:     return 8      // ms
            case .oscillation: return 0.3    // cm
            case .cadence:     return 3      // spm
            case .stride:      return 0.03   // m
            }
        }
    }

    struct Stat {
        let shoeID: String
        let count: Int
        let mean: Double
        let min: Double
        let max: Double
    }

    /// 폼 입력 → 신발이 기록된 러닝만. 신발은 러닝 일기(WorkoutStory.shoeID).
    static func runs(inputs: [FormInput], shoeOf: (UUID) -> String?, typeOf: (UUID) -> WorkoutType?) -> [Run] {
        inputs.compactMap { i in
            guard let shoe = shoeOf(i.activityID) else { return nil }
            let type = typeOf(i.activityID) ?? .general
            return Run(date: i.date, distanceM: i.distanceM, paceSecPerKm: i.paceSecPerKm,
                       avgHeartRate: i.avgHeartRate, cadence: i.avgCadence, stride: i.avgStrideLength,
                       contact: i.avgGroundContactTime, oscillation: i.avgVerticalOscillation,
                       shoeID: shoe, group: Group(type: type, bucket: .of(i.distanceM)))
        }
    }

    /// 이 신발이 뛴 묶음 — 횟수 많은 순
    static func groups(for shoeID: String, in runs: [Run]) -> [(group: Group, count: Int)] {
        var c: [Group: Int] = [:]
        for r in runs where r.shoeID == shoeID { c[r.group, default: 0] += 1 }
        let list: [(group: Group, count: Int)] = c.map { (group: $0.key, count: $0.value) }
        return list.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            if a.group.bucket != b.group.bucket { return a.group.bucket < b.group.bucket }
            return a.group.type.rawValue < b.group.type.rawValue
        }
    }

    /// 묶음 안 신발별 통계 — 값이 있는 러닝이 1회 이상인 신발만
    static func stats(_ metric: Metric, group: Group, runs: [Run]) -> [Stat] {
        var by: [String: [Double]] = [:]
        for r in runs where r.group == group {
            if let v = metric.value(r) { by[r.shoeID, default: []].append(v) }
        }
        return by.map { id, v in
            Stat(shoeID: id, count: v.count, mean: v.reduce(0, +) / Double(v.count), min: v.min()!, max: v.max()!)
        }.sorted { $0.count > $1.count }
    }

    /// 이 신발 vs 다른 신발(묶음 안 전체) 차이 — 다른 신발이 없으면 nil
    static func difference(_ metric: Metric, shoeID: String, group: Group, runs: [Run]) -> (diff: Double, mine: Int, others: Int)? {
        let inGroup = runs.filter { $0.group == group }
        let mine = inGroup.filter { $0.shoeID == shoeID }.compactMap(metric.value)
        let others = inGroup.filter { $0.shoeID != shoeID }.compactMap(metric.value)
        guard !mine.isEmpty, !others.isEmpty else { return nil }
        let m = mine.reduce(0, +) / Double(mine.count), o = others.reduce(0, +) / Double(others.count)
        return (m - o, mine.count, others.count)
    }

    /// 누적 km 순서 — 이 신발의 모든 러닝 거리를 날짜순으로 더한 값(그 러닝 포함) 위에 묶음 러닝의 지표를 찍는다
    static func wear(_ metric: Metric, shoeID: String, group: Group?, runs: [Run],
                     allShoeDistances: [(date: Date, meters: Double)]) -> [(km: Double, value: Double)] {
        let dists = allShoeDistances.sorted { $0.date < $1.date }
        func cumKm(at d: Date) -> Double { dists.filter { $0.date <= d }.reduce(0) { $0 + $1.meters } / 1000 }
        return runs
            .filter { $0.shoeID == shoeID && (group == nil || $0.group == group) }
            .sorted { $0.date < $1.date }
            .compactMap { r in metric.value(r).map { (cumKm(at: r.date), $0) } }
    }

    /// 앞 절반 vs 뒤 절반 평균 — 6회 이상일 때만(그보다 적으면 한두 번의 날씨·컨디션에 좌우된다)
    static func halves(_ pts: [(km: Double, value: Double)]) -> (early: Double, late: Double)? {
        guard pts.count >= 6 else { return nil }
        let h = pts.count / 2
        let e = pts.prefix(h).map(\.value), l = pts.suffix(pts.count - h).map(\.value)
        return (e.reduce(0, +) / Double(e.count), l.reduce(0, +) / Double(l.count))
    }
}
