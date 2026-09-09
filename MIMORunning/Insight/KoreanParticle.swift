import Foundation

/// 숫자 뒤에 붙는 한국어 조사 선택.
///
/// 숫자는 마지막 자릿수의 읽는 소리로 받침 유무가 정해진다.
/// 받침 없음(→ "는"): 2(이)·4(사)·5(오)·9(구) / 받침 있음(→ "은"): 0(영·공)·1(일)·3(삼)·6(육)·7(칠)·8(팔).
enum KoreanParticle {

    /// 주제격 조사 "은/는". 문자열의 마지막 숫자를 기준으로 판정하며, 숫자가 없으면 "는".
    static func topic(after numberText: String) -> String {
        guard let last = numberText.last(where: { $0.isNumber }),
              let digit = last.wholeNumberValue else { return "는" }
        switch digit {
        case 2, 4, 5, 9: return "는"
        default:         return "은"
        }
    }
}
