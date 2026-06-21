#if canImport(FoundationModels)
import FoundationModels

// Structured output type — @Generable ensures the model fills both fields.
@available(iOS 26, *)
@Generable(description: "러닝 인사이트 제목과 부연 문구")
struct AIInsightOutput {
    @Guide(description: """
        한국어 제목, 12자 이내, 담백한 감성.
        · 워크아웃 타입이 '일반 러닝'이면: 'OO 러닝' 형식 (예: '쌓이는 러닝', '한계를 미는 러닝').
        · 워크아웃 타입이 인터벌/롱런/회복런/템포런이면: '[동사구]+[타입명]' 형식 (예: '심장을 끌어올린 인터벌', '멀리 나아간 롱런', '숨을 고른 이지런', '리듬을 탄 템포').
          이때 '꾸준함', '효율', '자산', '한계', '경계' 같은 일반 테마 단어를 타입명에 붙이면 절대 안 됨.
        """)
    var title: String

    @Guide(description: "제공된 수치·사실만 활용한 한 줄 부연, 30자 이내")
    var detail: String
}

@available(iOS 26, *)
enum InsightAIGenerator {

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Rewrites `base` title/detail with on-device AI.
    /// Returns nil when unavailable or generation fails; caller keeps rule-based result.
    static func enhance(_ base: InsightResult) async -> InsightResult? {
        guard isAvailable else { return nil }

        let instructions = """
            당신은 러닝 앱 "미모러닝"의 인사이트 카피라이터입니다. You MUST respond in Korean.
            규칙 엔진이 계산한 테마와 사실을 받아 제목과 부연 문구를 자연스럽게 재표현합니다.
            규칙:
            · 부연: 제공된 수치·사실만 사용, 절대 없는 수치를 만들어내지 말 것, 30자 이내
            · 제목 형식:
              - 워크아웃 타입이 '일반 러닝'이면 → 'OO 러닝' 형식, 12자 이내, 담백하고 철학적인 톤
              - 워크아웃 타입이 인터벌/롱런/회복런/템포런이면 → 반드시 '[동사구]+[타입명]' 형식만 사용
                타입명: 인터벌→인터벌, 롱런→롱런, 회복런→이지런, 템포런→템포
                금지: '꾸준함 인터벌', '효율 롱런', '자산 인터벌' 같이 일반 테마 단어를 타입명에 붙이는 것
              - 강한 성취(첫 달성·페이스 PR) + 특정 타입이면 결합 허용: '기록을 깬 인터벌', '기록을 쓴 롱런'
            스타일 예시(제목 / 부연):
            일반 러닝 — 한계를 미는 러닝 / 최근 5km 중 가장 빠른 페이스
            일반 러닝 — 쌓이는 러닝 / 4주 연속 달리기 중
            일반 러닝 — 경계를 넓힌 러닝 / 이번 달 최장 거리 12.3km
            인터벌 — 심장을 끌어올린 인터벌 / 400m×6, 최고 1'42"
            인터벌 — 기록을 깬 인터벌 / 동일 거리 페이스 갱신
            롱런 — 멀리 나아간 롱런 / 이번 달 최장 거리 18km
            회복런 — 숨을 고른 이지런 / 낮은 강도로 다음 훈련을 준비
            템포런 — 리듬을 탄 템포 / 균일하게 밀어붙인 8km
            """

        let prompt = """
            테마: \(themeKorean(base.theme))
            워크아웃 타입: \(workoutTypeKorean(base.workoutType))
            사실: \(base.detail)
            기존 제목 참고: \(base.title)
            """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: AIInsightOutput.self)
            let output = response.content
            guard !output.title.isEmpty, !output.detail.isEmpty else { return nil }
            return InsightResult(theme: base.theme, workoutType: base.workoutType, title: output.title, detail: output.detail)
        } catch {
            return nil
        }
    }

    private static func workoutTypeKorean(_ type: WorkoutType) -> String {
        switch type {
        case .interval: "인터벌"
        case .longRun:  "롱런"
        case .easy:     "회복런"
        case .tempo:    "템포런"
        case .general:  "일반 러닝"
        }
    }

    private static func themeKorean(_ theme: InsightTheme) -> String {
        switch theme {
        case .firstAchievement:  "생애 첫 거리 달성"
        case .recordImproved:    "기록 향상 (페이스 PR)"
        case .adverseCondition:  "악조건 극복"
        case .distanceExpanded:  "이번 달 최장 거리"
        case .consistent:        "꾸준함·연속 달리기"
        case .recovery:          "회복 런 (낮은 강도)"
        case .raceDay:           "대회 완주"
        case .default:           "일반 달리기"
        }
    }
}
#endif
