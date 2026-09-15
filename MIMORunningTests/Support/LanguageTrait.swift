import Testing
@testable import MIMORunning

/// 테스트의 언어를 태스크 로컬로 고정하는 트레이트.
///
/// `AppLanguage.shared.isEnglish`는 프로세스 전역이라 스위트가 병렬로 돌면 한 스위트의 영어 전환이
/// 다른 스위트의 한국어 검사로 새어 들어갔다. 이 트레이트는 전역을 건드리지 않고
/// `AppLanguage.$override`를 테스트 본문(및 그 안에서 만든 자식 태스크)에만 묶는다.
///
/// - `.korean` / `.english`: 스위트나 테스트에 붙인다. 스위트에 붙이면 안의 모든 테스트에 상속.
/// - `inEnglish { }` / `inKorean { }`: 한 테스트 안에서 일부만 다른 언어로 확인할 때 인라인으로.
struct LanguageTrait: SuiteTrait, TestTrait, TestScoping {
    let isEnglish: Bool

    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?,
                      performing function: @concurrent @Sendable () async throws -> Void) async throws {
        try await AppLanguage.$override.withValue(isEnglish) {
            try await function()
        }
    }
}

extension Trait where Self == LanguageTrait {
    /// 스위트/테스트 전체를 한국어로 고정.
    static var korean: Self { LanguageTrait(isEnglish: false) }
    /// 스위트/테스트 전체를 영어로 고정.
    static var english: Self { LanguageTrait(isEnglish: true) }
}

/// `body`를 영어로 실행한다. 스위트가 `.korean`이어도 이 블록 안에서는 영어.
func inEnglish<T>(_ body: () throws -> T) rethrows -> T {
    try AppLanguage.$override.withValue(true) { try body() }
}

/// `body`를 한국어로 실행한다.
func inKorean<T>(_ body: () throws -> T) rethrows -> T {
    try AppLanguage.$override.withValue(false) { try body() }
}
