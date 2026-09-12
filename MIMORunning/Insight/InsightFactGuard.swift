import Foundation

/// AI가 다시 쓴 부연 문구에 **원문에 없는 숫자**가 섞였는지 본다.
///
/// 실제로 난 일: 규칙 엔진이 "최근 동일 거리 중 가장 빠른 페이스 6'16""이라고 계산한 16km 러닝을
/// 온디바이스 모델이 "최근 5km 중 가장 빠른 페이스 6'16"으로 고쳐 썼다. 프롬프트의 스타일 예시
/// "최근 5km 중 …"에서 5km를 그대로 베낀 것이다. 프롬프트에 "없는 수치를 만들지 말 것"이라고
/// 적어도 모델은 지키지 않는다 — 결과를 검사해서 어긋나면 규칙 엔진 문구로 되돌린다.
enum InsightFactGuard {

    /// 문자열 안의 숫자 덩어리(연속된 숫자) 집합. "6'16"" → {"6","16"}, "1:40:41" → {"1","40","41"}.
    static func digitRuns(in text: String) -> Set<String> {
        var runs = Set<String>()
        var current = ""
        for ch in text {
            if ch.isNumber { current.append(ch) }
            else if !current.isEmpty { runs.insert(current); current = "" }
        }
        if !current.isEmpty { runs.insert(current) }
        return runs
    }

    /// `output`의 모든 숫자가 `source`에도 있으면 true. 하나라도 새 숫자가 있으면 false.
    static func numbersAreGrounded(output: String, source: String) -> Bool {
        digitRuns(in: output).isSubset(of: digitRuns(in: source))
    }
}
