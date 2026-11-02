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

    static func runValue(_ r: RunRow, thresholdPace: Double, heat: MRHeatHRModel) -> RunValue? {
        guard r.type != .interval else { return nil }
        let lo = thresholdPace + bandLoSec, hi = thresholdPace + bandHiSec
        let inBand = r.kms.filter { $0.paceSec >= lo && $0.paceSec <= hi }
        guard inBand.count >= minKmPerRun else { return nil }
        let raw = mrMedian(inBand.map(\.hr))
        return RunValue(date: r.date, hr: heat.toRef(raw, tempC: r.tempC), rawHR: raw,
                        paceSec: mrMedian(inBand.map(\.paceSec)), kmCount: inBand.count)
    }

    static func monthly(_ runs: [RunRow], thresholdPace: Double, heat: MRHeatHRModel,
                        calendar cal: Calendar = .current) -> [Month] {
        let values = runs.compactMap { runValue($0, thresholdPace: thresholdPace, heat: heat) }
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
    static var rows: [MRTempoEfficiency.RunRow]? { didSet { log() } }
    private static var logged = false

    private static func log() {
        guard !logged, let t = thresholdPace, let h = heat, let rows else { return }
        logged = true
        let lo = mrFormatPace(t + MRTempoEfficiency.bandLoSec), hi = mrFormatPace(t + MRTempoEfficiency.bandHiSec)
        let kmTotal = rows.map(\.kms.count).reduce(0, +)
        print("[템포효율] 역치 \(mrFormatPace(t)) → 띠 \(lo)~\(hi) · 러닝 \(rows.count)건(km3~10 심박 있는 km \(kmTotal)) · 기온 보정 \(h.ok ? String(format: "%.2fbpm/°C%@", h.bpmPerC, h.isFallback ? "(문헌)" : "") : "없음")")
        let df = DateFormatter(); df.dateFormat = "M/d"
        let values = rows.compactMap { MRTempoEfficiency.runValue($0, thresholdPace: t, heat: h) }
        for v in values {
            let type = rows.first { $0.date == v.date }?.type?.koreanLabel ?? "?"
            print("[템포효율:러닝] \(df.string(from: v.date)) \(type) · km \(v.kmCount)개 \(mrFormatPace(v.paceSec)) · 심박 \(Int(v.rawHR.rounded())) → 15°C \(Int(v.hr.rounded()))")
        }
        let mf = DateFormatter(); mf.dateFormat = "yy.MM"
        let months = MRTempoEfficiency.monthly(rows, thresholdPace: t, heat: h)
        let line = months.map { "\(mf.string(from: $0.monthStart)) \($0.runs)회·\($0.kmCount)km·\(Int($0.hr.rounded()))bpm" }
            .joined(separator: " / ")
        print("[템포효율:월] \(line.isEmpty ? "띠 안 러닝 없음" : line)")
        if let f = months.first, let l = months.last, months.count >= 2 {
            print("[템포효율:월] 처음→마지막 \(String(format: "%+.0f", l.hr - f.hr))bpm (판정 없음, 표본 확인용)")
        }
    }
}
#endif
