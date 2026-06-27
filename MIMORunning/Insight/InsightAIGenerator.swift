#if canImport(FoundationModels)
import Foundation
import FoundationModels

// Structured output type — @Generable ensures the model fills both fields.
@available(iOS 26, *)
@Generable(description: "러닝 인사이트 제목과 부연 문구")
struct AIInsightOutput {
    @Guide(description: """
        한국어 제목, 12자 이내, 담백한 감성.
        · 워크아웃 타입이 '일반 러닝'이면: 'OO 러닝' 형식 (예: '쌓이는 러닝', '한계를 미는 러닝').
        · 워크아웃 타입이 인터벌/롱런/회복런/템포런/빌드업/LSD/거리주이면: '[동사구]+[타입명]' 형식 (예: '심장을 끌어올린 인터벌', '멀리 나아간 롱런', '숨을 고른 이지런', '리듬을 탄 템포', '끝까지 올린 빌드업', '천천히 멀리 간 LSD', '레이스처럼 밀어붙인 거리주').
          이때 '꾸준함', '효율', '자산', '한계', '경계' 같은 일반 테마 단어를 타입명에 붙이면 절대 안 됨.
        """)
    var title: String

    @Guide(description: "제공된 수치·사실만 활용한 한 줄 부연, 30자 이내")
    var detail: String
}

@available(iOS 26, *)
@Generable(description: "2주 러닝 추세 격려 한 문장")
struct WeeklyCommentOutput {
    @Guide(description: "한국어 격려 한 문장, 25자 내외. 주어진 숫자만 쓸 것. 이모지 최대 1개.")
    var comment: String
}

@available(iOS 26, *)
enum InsightAIGenerator {

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Rewrites `base` title/detail with on-device AI.
    /// Returns nil when unavailable, English mode, or generation fails; caller keeps rule-based result.
    static func enhance(_ base: InsightResult) async -> InsightResult? {
        guard isAvailable else { return nil }
        // AI prompt is Korean-only; skip enhancement when English mode is active
        guard !AppLanguage.shared.isEnglish else { return nil }
        // Safety notes contain factual load/HR numbers — must not be creatively rewritten
        guard base.theme != .safety else { return nil }

        let instructions = """
            당신은 러닝 앱 "미모러닝"의 인사이트 카피라이터입니다. You MUST respond in Korean.
            규칙 엔진이 계산한 테마와 사실을 받아 제목과 부연 문구를 자연스럽게 재표현합니다.
            규칙:
            · 부연: 제공된 수치·사실만 사용, 절대 없는 수치를 만들어내지 말 것, 30자 이내
            · 제목 형식:
              - 워크아웃 타입이 '일반 러닝'이면 → 'OO 러닝' 형식, 12자 이내, 담백하고 철학적인 톤
              - 워크아웃 타입이 인터벌/롱런/회복런/템포런/빌드업/LSD/거리주이면 → 반드시 '[동사구]+[타입명]' 형식만 사용
                타입명: 인터벌→인터벌, 롱런→롱런, 회복런→이지런, 템포런→템포, 빌드업→빌드업, LSD→LSD, 거리주→거리주
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
            빌드업 — 끝까지 올린 빌드업 / 마지막 km 최고 페이스
            LSD — 천천히 멀리 간 LSD / 느리고 고르게 21km
            거리주 — 레이스처럼 밀어붙인 거리주 / 하프 거리 레이스페이스 완주
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
        case .interval:    "인터벌"
        case .longRun:     "롱런"
        case .easy:        "회복런"
        case .tempo:       "템포런"
        case .buildUp:     "빌드업"
        case .lsd:         "LSD"
        case .distanceRun: "거리주"
        case .general:     "일반 러닝"
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
        case .tradeoff:          "지표 트레이드오프 (예: 거리↑을 위한 의도적 페이스↓, 심폐 효율 향상)"
        case .periodPositive:    "월간 총량 하향이지만 긍정 요소 발견 (페이스·최고 거리·연속·이정표·회복)"
        case .safety:            "안전·환경 돌봄 (심박 상승·부하 급증·더위)"
        }
    }

    // MARK: - Weekly comment

    /// 2주 추세 패턴에서 격려 한 문장을 생성. nil이면 호출부가 템플릿을 유지.
    static func generateWeeklyComment(patternKey: String, factSummary: String) async -> String? {
        guard isAvailable else { return nil }
        guard !AppLanguage.shared.isEnglish else { return nil }
        guard !factSummary.isEmpty else { return nil }

        let instructions = """
            너는 러닝 앱 "미모러닝"의 따뜻한 코치다. 주어진 2주 훈련 사실로 격려 한 문장을 쓴다.
            규칙:
            1) 주어진 숫자 외의 수치를 절대 만들지 마라.
            2) '더 빨리', '더 멀리', '빠르게', '더 많이', '더 길게', '치고 나가', '위험', '과훈련', '부상' 같은 압박·경고·결과 표현 금지.
            3) 절대적 기준이 아닌 본인의 2주 변화만 말한다.
            4) 한국어 한 문장, 18~35자. 명사 나열이나 감탄사가 아니라 완결된 격려 문장으로 쓴다. 예: '힘있게 밀어내며 발걸음이 가벼워졌어요' 같은 톤.
            5) 이모지는 최대 1개.
            6) 주어진 사실에 나온 지표(파워·접촉시간·보폭 등)의 의미만 표현하라. 사실에 없는 속도·거리·페이스를 언급하지 마라.
            7) 같은 단어를 반복하지 마라.
            8) '효율 향상!', '최고!' 같은 헤드라인·구호 형태 금지. 반드시 서술형 문장으로 끝낸다.
            """
        let guide = patternGuide(patternKey)
        let prompt = "패턴: \(weeklyPatternKorean(patternKey)). \(guide) 사실: \(factSummary). 이 사실로 격려 한 문장."

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: WeeklyCommentOutput.self)
            let text = response.content.comment
            guard validateWeeklyComment(text, factSummary: factSummary, patternKey: patternKey) else { return nil }
            return text
        } catch {
            return nil
        }
    }

    private static func patternGuide(_ key: String) -> String {
        switch key {
        case "economy":    return "이 패턴은 '효율·추진력·가벼움'에 대한 것이다. 속도나 거리가 아니다."
        case "speed":      return "이 패턴은 '페이스 향상·수월함'에 대한 것이다."
        case "form":       return "이 패턴은 '보폭·자세·폼 안정'에 대한 것이다. 속도나 거리가 아니다."
        case "cardio":     return "이 패턴은 '심폐·유산소 향상'에 대한 것이다."
        case "easy":       return "이 패턴은 '편안한 회복·여유'에 대한 것이다. 빠르게나 멀리가 아니다."
        case "streak":     return "이 패턴은 '꾸준한 연속'에 대한 것이다."
        case "consistent": return "이 패턴은 '꾸준한 훈련 횟수'에 대한 것이다."
        default:           return ""
        }
    }

    private static func weeklyPatternKorean(_ key: String) -> String {
        switch key {
        case "economy":    return "러닝 이코노미 향상"
        case "speed":      return "페이스 향상"
        case "form":       return "폼 개선"
        case "cardio":     return "심폐 향상"
        case "easy":       return "이지런 주간"
        case "streak":     return "연속 달리기"
        case "consistent": return "꾸준한 훈련"
        default:           return "달리기"
        }
    }

    private static func requiredVocab(for key: String) -> [String] {
        switch key {
        case "economy":    return ["힘", "추진", "밀어", "접촉", "가벼", "효율", "이코노미"]
        case "form":       return ["보폭", "자세", "폼", "케이던스", "안정"]
        case "speed":      return ["페이스", "빨라", "같은 노력", "수월"]
        case "cardio":     return ["심폐", "유산소", "숨", "오래"]
        case "easy":       return ["편하", "가볍게", "회복", "여유", "천천"]
        case "streak":     return ["연속", "꾸준", "이어", "쉬지"]
        case "consistent": return ["꾸준", "쌓이", "차곡"]
        default:           return []
        }
    }

    private static func validateWeeklyComment(_ text: String, factSummary: String, patternKey: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // 최소 글자수: 빈약한 단문·헤드라인 차단 (공백 제외)
        guard trimmed.filter({ !$0.isWhitespace }).count >= 12 else { return false }
        // 종결어미 검증: 완결 격려 문장 강제 (이모지가 뒤에 올 수 있으므로 뒤 10자 안에 '요' 확인)
        let tail = String(trimmed.suffix(10))
        guard tail.contains("요") || trimmed.hasSuffix("다") else { return false }
        // 문장 수 제한
        let sentenceEnders = CharacterSet(charactersIn: ".。!?！？\n")
        let segments = trimmed.components(separatedBy: sentenceEnders)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard segments.count <= 2 else { return false }
        // 금지어 — 압박·결과·반복 차단
        let banned = ["더 멀리", "멀리", "더 빨리", "빠르게", "더 많이", "더 길게", "치고", "위험", "과훈련", "부상"]
        for word in banned where trimmed.contains(word) { return false }
        // 숫자 조작 차단
        let allowed = extractNumbers(from: factSummary)
        let aiNums  = extractNumbers(from: trimmed)
        guard aiNums.isSubset(of: allowed) else { return false }
        // 양성 검증: 패턴 필수 어휘군 중 하나 이상 포함
        let vocab = requiredVocab(for: patternKey)
        if !vocab.isEmpty && !vocab.contains(where: { trimmed.contains($0) }) { return false }
        return true
    }

    private static func extractNumbers(from text: String) -> Set<Int> {
        var result = Set<Int>()
        guard let regex = try? NSRegularExpression(pattern: #"\d+"#) else { return result }
        regex.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, _ in
            if let match, let r = Range(match.range, in: text), let n = Int(text[r]) {
                result.insert(n)
            }
        }
        return result
    }
}
#endif
