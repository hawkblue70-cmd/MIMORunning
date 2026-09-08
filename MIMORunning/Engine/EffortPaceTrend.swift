import Foundation

/// "같은 노력(강도 2~4)으로 더 빨라졌나" — 기존 폼 판정기(mrFormShift: 최근 3개월 vs 이전 3개월, MDC₉₅)를 재사용.
/// 좋아진 쪽(페이스 감소)만 문장을 만든다. 나빠진 쪽은 침묵.
enum EffortPaceTrend {
    static let easyRange = 2...4
    /// higherMeansMoreBounce=true: 값이 높을수록 나쁨(페이스 sec/km)
    static let metric = MRFormMetric(key: "easyPace", label: "쉬운 날 페이스", unit: "s/km", higherMeansMoreBounce: true)

    static func residuals(points: [(date: Date, value: Double)]) -> [MRFormResidual] {
        points.map { MRFormResidual(date: $0.date, value: $0.value) }
    }

    static func observation(shift: MRFormShift) -> (text: String, basis: String)? {
        guard shift.metric.key == metric.key, shift.isReal, shift.delta < 0 else { return nil }
        let L = AppLanguage.shared
        let d = Int((-shift.delta).rounded())
        let text = L.isEnglish
            ? "In runs at effort 2–4, your pace got \(d)s/km faster over 3 months."
            : "강도 2~4로 뛴 러닝의 페이스가 3개월 새 \(d)초 빨라졌어요."
        let basis = String(format: "Δ%+.1fs/km · MDC %.1f · Foster 2001", shift.delta, shift.mdc)
        return (text, basis)
    }
}
