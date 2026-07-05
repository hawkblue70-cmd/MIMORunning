#if canImport(FoundationModels)
import Foundation
import FoundationModels

// Structured output type — @Generable ensures the model fills the detail field.
// Title is always kept verbatim from the rule engine; only detail is AI-rewritten.
@available(iOS 26, *)
@Generable(description: "러닝 인사이트 부연 문구")
struct AIInsightOutput {
    @Guide(description: "제공된 수치·사실만 활용한 한 줄 부연, 30자 이내")
    var detail: String
}

@available(iOS 26, *)
@Generable(description: "2주 러닝 훈련 총평 2~3문장")
struct WeeklyCommentOutput {
    @Guide(description: "한국어 2~3문장 총평, 전체 30~80자. 구성→신호→흐름 순. 주어진 숫자만 쓸 것. 이모지 금지.")
    var comment: String
}

@available(iOS 26, *)
enum InsightAIGenerator {

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Rewrites `base.detail` with on-device AI; `base.title` is always kept verbatim.
    /// Returns nil when unavailable, English mode, or generation fails; caller keeps rule-based result.
    static func enhance(_ base: InsightResult) async -> InsightResult? {
        guard isAvailable else { return nil }
        // AI prompt is Korean-only; skip enhancement when English mode is active
        guard !AppLanguage.shared.isEnglish else { return nil }
        // Safety notes contain factual load/HR numbers — must not be creatively rewritten
        guard base.theme != .safety else { return nil }

        let instructions = """
            당신은 러닝 앱 "미모러닝"의 인사이트 카피라이터입니다. You MUST respond in Korean.
            규칙 엔진이 계산한 테마와 사실을 받아 부연 문구를 자연스럽게 재표현합니다.
            규칙:
            · 부연: 제공된 수치·사실만 사용, 절대 없는 수치를 만들어내지 말 것, 30자 이내
            스타일 예시(부연):
            최근 5km 중 가장 빠른 페이스
            4주 연속 달리기 중
            이번 달 최장 거리 12.3km
            400m×6, 최고 1'42"
            심박 최고 178bpm
            """

        let prompt = """
            테마: \(themeKorean(base.theme))
            사실: \(base.detail)
            """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: AIInsightOutput.self)
            let output = response.content
            guard !output.detail.isEmpty else { return nil }
            return InsightResult(theme: base.theme, workoutType: base.workoutType, title: base.title, detail: output.detail)
        } catch {
            return nil
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
        case .rarityFact:        "희소성 사실 (기온 극값·시간대 재회)"
        case .milestone:         "평생 누적 이정표 (50km 단위 최초 돌파)"
        case .subThreshold:      "서브T 절제 인정 (인터벌 구간 페이스 일관성)"
        }
    }

    // MARK: - Weekly comment

    /// 2주 추세 패턴에서 격려 한 문장을 생성. nil이면 호출부가 템플릿을 유지.
    static func generateWeeklyComment(patternKey: String, factSummary: String) async -> String? {
        // [AI-A] 가용성 확인 — availability enum 값 그대로 출력
        let availability = SystemLanguageModel.default.availability
        if availability == .available {
            #if DEBUG
            print("[AI-A] 가용=.available 패턴=\(patternKey) 양성어휘=\(requiredVocab(for: patternKey))")
            #endif
        } else {
            #if DEBUG
            print("[AI-A] 미지원: \(availability)")
            #endif
            return nil
        }
        guard !AppLanguage.shared.isEnglish else { return nil }
        guard !factSummary.isEmpty else { return nil }

        let instructions = """
            너는 러닝 앱 "미모러닝"의 따뜻한 코치다. 주어진 2주 훈련 사실로 총평을 쓴다.
            출력 규격:
            - 출력은 2~3문장, 전체 30~80자.
            - 각 문장은 '~요' 또는 '~네요'로 끝낸다.
            - 이모지, 느낌표, 특수문자를 쓰지 않는다.
            - 주어진 사실의 수치를 최소 한 곳에 포함한다.
            규칙:
            1) 주어진 숫자 외의 수치를 절대 만들지 마라.
            2) '더 빨리', '더 멀리', '빠르게', '더 많이', '더 길게', '치고 나가', '위험', '과훈련', '부상' 같은 압박·경고 표현 금지.
            3) 절대적 기준이 아닌 본인의 2주 변화만 말한다.
            4) 같은 단어를 반복하지 마라.
            5) 헤드라인·구호 형태 금지. 반드시 서술형 문장으로 끝낸다.
            좋은 예: "인터벌 2회를 섞은 5회 구성이었어요. 보폭이 늘어나는 흐름이에요. 4주째 이어지고 있어요."
            나쁜 예: "5회 완주! 최고였어요."
            """
        let guide = patternGuide(patternKey)
        let prompt = "패턴: \(weeklyPatternKorean(patternKey)). \(guide) 사실: \(factSummary). 이 사실로 2~3문장 총평."

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: WeeklyCommentOutput.self)
            let text = response.content.comment
            let (valid, reason) = validateWeeklyCommentDetailed(text, factSummary: factSummary, patternKey: patternKey)
            if valid { return text }

            // [AI-C] 1차 탈락 → 사유 명시 재시도
            #if DEBUG
            print("[AI-C] 1차 탈락 원문=「\(text)」 사유=\(reason ?? "unknown") → 재시도")
            #endif
            let retryHint: String
            if let r = reason {
                if r.contains("길이 미달") {
                    retryHint = "이전 출력은 너무 짧았다. 30자 이상 2~3문장으로 다시 써라."
                } else if r.contains("문장수 부족") {
                    retryHint = "이전 출력이 문장 1개뿐이었다. 반드시 2~3문장으로 나눠서 다시 써라."
                } else if r.contains("종결어미") {
                    retryHint = "이전 출력이 '요' 또는 '다'로 끝나지 않았다. 반드시 '~요'로 끝내라."
                } else if r.contains("양성어휘") {
                    retryHint = "이전 출력에 필수 어휘(\(requiredVocab(for: patternKey).joined(separator: "/")))가 없었다. 이 중 하나를 포함해서 다시 써라."
                } else if r.contains("금지어") {
                    retryHint = "이전 출력에 금지어가 있었다. 압박·결과 표현 없이 다시 써라."
                } else {
                    retryHint = "이전 출력(\(r))을 수정해서 다시 써라."
                }
            } else {
                retryHint = "이전 출력을 규칙에 맞게 다시 써라."
            }
            let retryResponse = try await session.respond(to: retryHint, generating: WeeklyCommentOutput.self)
            let retryText = retryResponse.content.comment
            let (retryValid, retryReason) = validateWeeklyCommentDetailed(retryText, factSummary: factSummary, patternKey: patternKey)
            if retryValid {
                #if DEBUG
                print("[AI-C] 재시도 성공 원문=「\(retryText)」")
                #endif
                return retryText
            }
            #if DEBUG
            print("[AI-C] 재시도 탈락 원문=「\(retryText)」 사유=\(retryReason ?? "unknown")")
            #endif
            return nil
        } catch {
            #if DEBUG
            print("[AI-B] 생성 실패: \(error)")
            #endif
            return nil
        }
    }

    private static func patternGuide(_ key: String) -> String {
        switch key {
        case "economy":           return "이 패턴은 '효율·추진력·가벼움'에 대한 것이다. 속도나 거리가 아니다."
        case "speed":             return "이 패턴은 '페이스 향상·수월함'에 대한 것이다."
        case "form":              return "이 패턴은 '보폭·자세·폼 안정'에 대한 것이다. 속도나 거리가 아니다."
        case "cardio":            return "이 패턴은 '심폐·유산소 향상'에 대한 것이다."
        case "easy":              return "이 패턴은 '편안한 회복·여유'에 대한 것이다. 빠르게나 멀리가 아니다."
        case "streak":            return "이 패턴은 '꾸준한 연속'에 대한 것이다."
        case "consistent":        return "이 패턴은 '꾸준한 훈련 횟수'에 대한 것이다."
        case "fatigueSign":       return "이 패턴은 '폼 피로 관찰'에 대한 것이다. 단정·경고가 아니라 관찰과 부드러운 제안만 한다."
        case "overstride":        return "이 패턴은 '착지·발 위치 관찰'에 대한 것이다. 부드러운 폼 제안만 하고 결함을 진단하지 않는다."
        case "economyPlus":       return "이 패턴은 '러닝 이코노미 자연 개선'에 대한 것이다. 효율·가벼움·접촉에 집중한다."
        case "propulsion":        return "이 패턴은 '추진력·보폭 성장'에 대한 것이다. 보폭이 자란다는 것을 긍정적으로 표현한다."
        case "turnover":          return "이 패턴은 '케이던스·잰걸음 발달'에 대한 것이다. 리듬과 발 회전에 집중한다."
        case "compositionChange": return "이 패턴은 '훈련 구성 변화·적응'에 대한 것이다. 지표 출렁임이 자연스럽다고 안심시킨다."
        default:                  return ""
        }
    }

    private static func weeklyPatternKorean(_ key: String) -> String {
        switch key {
        case "economy":           return "러닝 이코노미 향상"
        case "speed":             return "페이스 향상"
        case "form":              return "폼 개선"
        case "cardio":            return "심폐 향상"
        case "easy":              return "이지런 주간"
        case "streak":            return "연속 달리기"
        case "consistent":        return "꾸준한 훈련"
        case "fatigueSign":       return "폼 피로 신호"
        case "overstride":        return "오버스트라이드 신호"
        case "economyPlus":       return "이코노미 개선"
        case "propulsion":        return "추진력 발달"
        case "turnover":          return "턴오버 개선"
        case "compositionChange": return "훈련 구성 변화"
        default:                  return "달리기"
        }
    }

    private static func requiredVocab(for key: String) -> [String] {
        switch key {
        case "economy":           return ["힘", "추진", "밀어", "접촉", "가벼", "효율", "이코노미"]
        case "form":              return ["보폭", "자세", "폼", "케이던스", "안정"]
        case "speed":             return ["페이스", "빨라", "같은 노력", "수월"]
        case "cardio":            return ["심폐", "유산소", "숨", "오래"]
        case "easy":              return ["편하", "가볍게", "회복", "여유", "천천"]
        case "streak":            return ["연속", "꾸준", "이어", "쉬지"]
        case "consistent":        return ["꾸준", "쌓이", "차곡"]
        case "fatigueSign":       return ["회복", "가볍", "쉬", "몸", "신호"]
        case "overstride":        return ["착지", "발", "몸 아래", "케이던스", "회전"]
        case "economyPlus":       return ["효율", "가벼", "접촉", "이코노미", "조용"]
        case "propulsion":        return ["추진", "보폭", "리듬", "자라", "힘"]
        case "turnover":          return ["리듬", "잰걸음", "케이던스", "발 회전", "분산"]
        case "compositionChange": return ["강약", "훈련", "자연", "적응", "출렁"]
        default:                  return []
        }
    }

    /// 검증 결과와 탈락 사유를 함께 반환. [AI-C] 진단에 사용.
    private static func validateWeeklyCommentDetailed(_ text: String, factSummary: String, patternKey: String) -> (valid: Bool, reason: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (false, "빈 문자열") }
        let charCount = trimmed.filter({ !$0.isWhitespace }).count
        guard charCount >= 25 else { return (false, "길이 미달: \(charCount)자 < 25자") }
        let tail = String(trimmed.suffix(10))
        guard tail.contains("요") || trimmed.hasSuffix("다") else {
            return (false, "종결어미 없음: 뒤10자=「\(tail)」")
        }
        let sentenceEnders = CharacterSet(charactersIn: ".。!?！？\n")
        let segments = trimmed.components(separatedBy: sentenceEnders)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard segments.count >= 2 else { return (false, "문장수 부족: \(segments.count)개 < 2개") }
        guard segments.count <= 3 else { return (false, "문장수 초과: \(segments.count)개 > 3개") }
        let banned = ["더 멀리", "멀리", "더 빨리", "빠르게", "더 많이", "더 길게", "치고", "위험", "과훈련", "부상"]
        for word in banned where trimmed.contains(word) {
            return (false, "금지어: 「\(word)」")
        }
        let allowed = extractNumbers(from: factSummary)
        let aiNums  = extractNumbers(from: trimmed)
        guard aiNums.isSubset(of: allowed) else {
            return (false, "숫자조작: AI=\(aiNums.sorted()) 허용=\(allowed.sorted())")
        }
        let vocab = requiredVocab(for: patternKey)
        if !vocab.isEmpty && !vocab.contains(where: { trimmed.contains($0) }) {
            return (false, "양성어휘 없음: 필수=\(vocab)")
        }
        return (true, nil)
    }

    private static func validateWeeklyComment(_ text: String, factSummary: String, patternKey: String) -> Bool {
        validateWeeklyCommentDetailed(text, factSummary: factSummary, patternKey: patternKey).valid
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
