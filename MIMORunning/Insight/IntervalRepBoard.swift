import Foundation
import CoreGraphics

/// 경로 영상 인터벌 회차 보드 — 운동 구간이 끝나는 지점을 지도가 지날 때 한 줄씩 나타난다.
/// 뷰(`IntervalRepBoardView`)와 출력(`RouteVideoExportService`)은 이 값만 읽는다. 운동 구간 2개 미만이면 nil.
struct IntervalRepBoard: Equatable {
    struct Rep: Equatable {
        let index: Int              // 1부터
        let distanceM: Double?
        let paceSecPerKm: Double?
        let avgHeartRate: Int?
        /// 이 회차가 끝나는 지점의 경로 진행 비율(0…1). 거리 누적이 가능하면 거리 비율, 아니면 시간 비율.
        let revealFraction: Double
    }

    let reps: [Rep]
    /// 모든 운동 구간 거리가 ±5% 안에서 같으면 대표 거리(표준 거리로 반올림), 아니면 nil.
    let uniformDistanceM: Double?
    let averagePaceSecPerKm: Double?
    /// 운동이 아닌 구간(준비·회복·정리)의 시간 범위 — 경로를 흐리게 그리는 데 쓴다. 러닝 시작 기준 초.
    let dimTimeRanges: [ClosedRange<TimeInterval>]

    /// 한 열에 넣는 최대 회차 수. 넘으면 두 열(쌍)로.
    static let maxSingleColumnRows = 10

    // MARK: - 생성

    static func make(segments: [IntervalSegment], activityStart: Date,
                     totalDistanceM: Double, totalDuration: TimeInterval) -> IntervalRepBoard? {
        let ordered = segments.sorted { $0.startDate < $1.startDate }
        let work = ordered.filter { $0.stepLabel == "운동" }
        guard work.count >= 2, totalDuration > 0 else { return nil }

        // 누적 거리 — 모든 구간에 거리가 있고 합이 양수일 때만 거리 비율을 쓴다
        let allHaveDistance = ordered.allSatisfy { ($0.distanceM ?? 0) > 0 }
        let distanceSum = ordered.compactMap(\.distanceM).reduce(0, +)
        let useDistance = allHaveDistance && distanceSum > 0
        let denominator = useDistance ? max(distanceSum, totalDistanceM) : totalDuration

        var cumulative = 0.0
        var reps: [Rep] = []
        var dims: [ClosedRange<TimeInterval>] = []
        for seg in ordered {
            let isWork = seg.stepLabel == "운동"
            let endValue: Double
            if useDistance {
                cumulative += seg.distanceM ?? 0
                endValue = cumulative
            } else {
                endValue = seg.endDate.timeIntervalSince(activityStart)
            }
            if isWork {
                reps.append(Rep(index: reps.count + 1, distanceM: seg.distanceM,
                                paceSecPerKm: seg.paceSecPerKm, avgHeartRate: seg.avgHeartRate,
                                revealFraction: min(max(endValue / denominator, 0), 1)))
            } else {
                let lo = max(0, seg.startDate.timeIntervalSince(activityStart))
                let hi = max(lo, seg.endDate.timeIntervalSince(activityStart))
                dims.append(lo...hi)
            }
        }

        let distances = work.compactMap(\.distanceM)
        var uniform: Double? = nil
        if distances.count == work.count, let lo = distances.min(), let hi = distances.max(), lo > 0, hi / lo <= 1.05 {
            uniform = Double(recognizedDistanceM(distances.reduce(0, +) / Double(distances.count)))
        }
        let paces = work.compactMap(\.paceSecPerKm)
        let avg = paces.isEmpty ? nil : paces.reduce(0, +) / Double(paces.count)
        return IntervalRepBoard(reps: reps, uniformDistanceM: uniform, averagePaceSecPerKm: avg, dimTimeRanges: dims)
    }

    /// 표준 거리(200·400·600·800·1000·1200·1600·2000·3000·5000m)에 8% 안이면 그 값, 아니면 100m(200m 미만은 50m) 단위 반올림.
    /// `ActivityDetailView.recognizedDistanceM`과 같은 규칙.
    static func recognizedDistanceM(_ d: Double) -> Int {
        let standards = [200, 400, 600, 800, 1000, 1200, 1600, 2000, 3000, 5000]
        if let snap = standards.first(where: { abs(Double($0) - d) / Double($0) <= 0.08 }) { return snap }
        return d >= 200 ? Int((d / 100).rounded()) * 100 : Int((d / 50).rounded()) * 50
    }

    // MARK: - 표시 규칙

    var columns: Int { reps.count > Self.maxSingleColumnRows ? 2 : 1 }
    /// 회차 칸 수(열이 둘이면 쌍 수) + 바닥글 1칸
    var slotCount: Int { Int(ceil(Double(reps.count) / Double(columns))) + 1 }
    /// 보인 회차 수로 열린 칸 수 — 마지막 회차가 보이면 바닥글 칸도 함께 열린다
    func revealedSlots(revealed: Int) -> Int {
        let n = min(max(revealed, 0), reps.count)
        guard n > 0 else { return 0 }
        let rowSlots = Int(ceil(Double(n) / Double(columns)))
        return n == reps.count ? rowSlots + 1 : rowSlots
    }
    var showsDistanceColumn: Bool { uniformDistanceM == nil }

    func revealedCount(progress: CGFloat) -> Int {
        let p = Double(progress)
        return reps.filter { $0.revealFraction <= p + 1e-9 }.count
    }

    func isDimmed(offset: TimeInterval) -> Bool {
        dimTimeRanges.contains { $0.contains(offset) }
    }

    // MARK: - 문장 (관찰 사실만)

    var headerText: String {
        let L = AppLanguage.shared
        if let d = uniformDistanceM {
            return "\(reps.count) × \(Self.distanceLabel(d))"
        }
        return L.s("인터벌 \(reps.count)회", "\(reps.count) intervals")
    }

    var footerText: String? {
        guard let avg = averagePaceSecPerKm else { return nil }
        let L = AppLanguage.shared
        return L.s("평균 \(Self.paceText(avg))", "avg \(Self.paceText(avg))")
    }

    static func distanceLabel(_ m: Double) -> String {
        if m >= 1000 {
            let km = m / 1000
            return km == km.rounded() ? "\(Int(km))km" : String(format: "%.1fkm", km)
        }
        return "\(Int(m.rounded()))m"
    }

    static func paceText(_ sec: Double) -> String {
        let i = Int(sec.rounded())
        return String(format: "%d'%02d\"", i / 60, i % 60)
    }
}
