import Foundation

/// "같은 노력(본인 이지런 강도 이하)으로 더 빨라졌나" — 기존 폼 판정기(mrFormShift: 최근 3개월 vs 이전 3개월, MDC₉₅)를 재사용.
/// 좋아진 쪽(페이스 감소)만 문장을 만든다. 나빠진 쪽은 침묵.
///
/// ⚠️ 통제되지 않은 교란 요인:
/// - 거리 믹스(짧은 이지런이 늘면 평균 페이스가 빨라 보임)·지형(고도)·날씨(기온·바람)를 보정하지 않는다.
/// - Apple 추정 강도는 심박·페이스에서 파생되므로, 그 강도로 거른 페이스를 다시 보는 데엔 약한 순환성이 있다.
/// 그래서 인과("좋아졌다")를 단정하지 않고, 개선 방향일 때만 관찰 문장을 말한다(악화는 침묵).
enum EffortPaceTrend {
    /// 본인 이지런 강도 중앙값을 못 구할 때의 고정 기준.
    static let fallbackCutoff = 4

    /// 본인 이지런(WorkoutType.easy/.lsd) 강도의 중앙값. 3건 미만이면 nil → 고정 4로 폴백.
    static func easyCutoff(easyRunEfforts: [Int]) -> Int? {
        guard easyRunEfforts.count >= 3 else { return nil }
        return Int(WorkoutTypeClassifier.median(easyRunEfforts.map(Double.init)).rounded())
    }

    static func isEasy(effort: Int, cutoff: Int?) -> Bool { effort <= (cutoff ?? fallbackCutoff) }

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

    /// `isPersonal`: cutoff가 본인 이지런 중앙값에서 나왔는지(false = 고정 4 폴백 → 괄호 설명 생략).
    static func observation(shift: MRFormShift, cutoff: Int, isPersonal: Bool) -> (text: String, basis: String)? {
        guard shift.metric.key == metric.key, shift.isReal, shift.delta < 0 else { return nil }
        let d = Int((-shift.delta).rounded())
        // 1초 미만은 "0초 빨라졌어요" 같은 무의미한 문장이 되므로 말하지 않는다.
        guard d >= 1 else { return nil }
        let L = AppLanguage.shared
        let text: String
        if L.isEnglish {
            text = isPersonal
                ? "In runs at effort ≤\(cutoff) (your easy-run level), pace got \(d)s/km faster over 3 months."
                : "In runs at effort ≤\(cutoff), pace got \(d)s/km faster over 3 months."
        } else {
            text = isPersonal
                ? "강도 \(cutoff) 이하(본인 이지런 기준)로 뛴 러닝의 페이스가 3개월 새 \(d)초/km 빨라졌어요."
                : "강도 \(cutoff) 이하로 뛴 러닝의 페이스가 3개월 새 \(d)초/km 빨라졌어요."
        }
        let basis = String(format: "Δ%+.1fs/km · MDC %.1f · Foster 2001", shift.delta, shift.mdc)
        return (text, basis)
    }
}
