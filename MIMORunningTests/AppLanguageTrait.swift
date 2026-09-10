import Testing
@testable import MIMORunning

/// 테스트가 볼 언어를 고정하는 트레이트.
///
/// 예전에는 각 테스트가 `AppLanguage.shared.isEnglish`(전역 싱글턴)를 직접 바꿨다.
/// `.serialized`는 **같은 스위트 안**에서만 순서를 보장하므로, 영어로 바꾼 스위트와
/// 한국어 문장을 기대하는 다른 스위트가 나란히 돌면서 서로의 언어를 덮어썼다.
///
/// 이 트레이트는 태스크 로컬 `AppLanguage.override`로 언어를 **주입**한다.
/// 병렬로 도는 테스트마다 값이 독립적이고, 전역 상태·UserDefaults를 전혀 건드리지 않는다.
struct AppLanguageTrait: TestTrait, SuiteTrait, TestScoping {
    let isEnglish: Bool

    /// 스위트에 붙이면 하위 테스트마다 개별로 적용된다.
    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?,
                      performing function: @concurrent @Sendable () async throws -> Void) async throws {
        try await AppLanguage.$override.withValue(isEnglish) {
            try await function()
        }
    }
}

extension Trait where Self == AppLanguageTrait {
    /// 한국어 문장을 기대하는 스위트에 붙인다.
    /// 개별 영어 테스트는 안쪽에서 `AppLanguage.$override.withValue(true)`로 덮어쓴다.
    static var korean: Self { AppLanguageTrait(isEnglish: false) }
}
