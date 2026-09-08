import Foundation

/// "같은 노력(강도 2~4)으로 더 빨라졌나" — 기존 폼 판정기(mrFormShift: 최근 3개월 vs 이전 3개월, MDC₉₅)를 재사용.
/// 좋아진 쪽(페이스 감소)만 문장을 만든다. 나빠진 쪽은 침묵.
///
/// ⚠️ 통제되지 않은 교란 요인:
/// - 거리 믹스(짧은 이지런이 늘면 평균 페이스가 빨라 보임)·지형(고도)·날씨(기온·바람)를 보정하지 않는다.
/// - Apple 추정 강도는 심박·페이스에서 파생되므로, 그 강도로 거른 페이스를 다시 보는 데엔 약한 순환성이 있다.
/// 그래서 인과("좋아졌다")를 단정하지 않고, 개선 방향일 때만 관찰 문장을 말한다(악화는 침묵).
enum EffortPaceTrend {
    static let easyRange = 2...4
    /// higherMeansMoreBounce=true: 값이 높을수록 나쁨(페이스 sec/km)
    static let metric = MRFormMetric(key: "easyPace", label: "쉬운 날 페이스", unit: "s/km", higherMeansMoreBounce: true)

    static func residuals(points: [(date: Date, value: Double)]) -> [MRFormResidual] {
        points.map { MRFormResidual(date: $0.date, value: $0.value) }
    }

    /// 차트 Y축용 페이스 라벨 — `m'ss"` (단위 없음).
    static func axisLabel(_ secPerKm: Double) -> String {
        let total = Int(secPerKm.rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60)
    }

    static func observation(shift: MRFormShift) -> (text: String, basis: String)? {
        guard shift.metric.key == metric.key, shift.isReal, shift.delta < 0 else { return nil }
        let d = Int((-shift.delta).rounded())
        // 1초 미만은 "0초 빨라졌어요" 같은 무의미한 문장이 되므로 말하지 않는다.
        guard d >= 1 else { return nil }
        let L = AppLanguage.shared
        let text = L.isEnglish
            ? "In runs at effort 2–4, your pace got \(d)s/km faster over 3 months."
            : "강도 2~4로 뛴 러닝의 페이스가 3개월 새 \(d)초/km 빨라졌어요."
        let basis = String(format: "Δ%+.1fs/km · MDC %.1f · Foster 2001", shift.delta, shift.mdc)
        return (text, basis)
    }
}
