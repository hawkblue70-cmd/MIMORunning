import Foundation

/// 대회 이름·종목 표시 규칙. 나 탭 참가 대회 기록과 대회 해마다 비교가 같은 함수를 쓴다.
///
/// 대회 DB 이름은 출처마다 표기가 달라 연도와 회차가 앞뒤·괄호 안에 붙는다.
/// 화면에는 그것을 뗀 이름을 쓴다. 저장된 이름은 바꾸지 않는다.
enum RaceDisplayName {

    /// 연도(위치 무관)와 회차를 뗀 표시 이름.
    /// "제46회 조선일보 춘천마라톤" → "조선일보 춘천마라톤"
    /// "2026 서울마라톤 (제96회 동아마라톤)" → "서울마라톤 (동아마라톤)"
    static func short(_ name: String) -> String {
        var s = name
        s = s.replacingOccurrences(of: #"(?<!\d)20\d{2}년?(?!\d)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\(\s*\d+\s*회\s*\)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"제\s*\d+\s*회\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\(\s*\)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? name : s
    }

    /// 공식 종목 거리(km) → "5K"·"10K"·"하프"·"풀"(영어 Half·Full). 표준 거리 ±2% 밖이면 "32K"·"10.9K".
    static func distanceLabel(km: Double) -> String {
        let L = AppLanguage.shared
        let standards: [(km: Double, label: String)] = [
            (5.0, "5K"), (10.0, "10K"),
            (21.0975, L.s("하프", "Half", ja: "ハーフ")), (42.195, L.s("풀", "Full", ja: "フル")),
        ]
        if let hit = standards.first(where: { abs($0.km - km) / $0.km <= 0.02 }) { return hit.label }
        if abs(km - km.rounded()) < 0.05 { return "\(Int(km.rounded()))K" }
        return String(format: "%.1fK", locale: Locale(identifier: "en_US_POSIX"), km)
    }
}
