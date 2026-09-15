import Foundation

// MARK: - App Language

@Observable final class AppLanguage {
    static let shared = AppLanguage()

    /// 테스트 전용 태스크 로컬 오버라이드 — `true`=영어, `false`=한국어, `nil`=앱 설정(`storedIsEnglish`).
    /// 스위프트 테스팅 스위트가 병렬로 돌 때 한 스위트의 언어 전환이 다른 스위트로 새지 않도록,
    /// 전역 값을 쓰지 않고 현재 태스크 트리에만 언어를 묶는다. 앱 코드에서는 항상 `nil`.
    @TaskLocal static var override: Bool? = nil

    /// 사용자가 고른 언어(앱 설정). UserDefaults `appLanguageIsEnglish`와 동기화.
    private var storedIsEnglish: Bool {
        didSet { UserDefaults.standard.set(storedIsEnglish, forKey: "appLanguageIsEnglish") }
    }

    /// 지금 이 문맥에서 유효한 언어 — 모든 읽기는 여기를 거친다(`s(_:_:)`, 날짜 포맷, 엔진·뷰 전부).
    /// 읽기: 태스크 로컬 오버라이드가 있으면 그것, 없으면 저장된 설정. 쓰기: 저장된 설정(UserDefaults)만 바꾼다.
    var isEnglish: Bool {
        get { Self.override ?? storedIsEnglish }
        set { storedIsEnglish = newValue }
    }

    private init() {
        storedIsEnglish = UserDefaults.standard.bool(forKey: "appLanguageIsEnglish")
    }

    /// Returns `ko` when Korean is active, `en` when English is active.
    func s(_ ko: String, _ en: String) -> String {
        isEnglish ? en : ko
    }
}

// MARK: - Date helpers for share cards

extension Date {
    /// "yyyy. M. d  a h:mm" (KO) / "MMM d, yyyy  h:mm a" (EN)
    var cardDateTimeString: String {
        let df = DateFormatter()
        if AppLanguage.shared.isEnglish {
            df.locale = Locale(identifier: "en_US")
            df.dateFormat = "MMM d, yyyy  h:mm a"
        } else {
            df.locale = Locale(identifier: "ko_KR")
            df.dateFormat = "yyyy. M. d  a h:mm"
        }
        return df.string(from: self)
    }

    /// "yyyy. M. d" (KO) / "MMM d, yyyy" (EN)
    var cardDateString: String {
        let df = DateFormatter()
        if AppLanguage.shared.isEnglish {
            df.locale = Locale(identifier: "en_US")
            df.dateFormat = "MMM d, yyyy"
        } else {
            df.locale = Locale(identifier: "ko_KR")
            df.dateFormat = "yyyy. M. d"
        }
        return df.string(from: self)
    }

    /// "a h:mm" (KO) / "h:mm a" (EN)
    var cardTimeString: String {
        let df = DateFormatter()
        if AppLanguage.shared.isEnglish {
            df.locale = Locale(identifier: "en_US")
            df.dateFormat = "h:mm a"
        } else {
            df.locale = Locale(identifier: "ko_KR")
            df.dateFormat = "a h:mm"
        }
        return df.string(from: self)
    }

    /// 요일 한자 (일/월/화/수/목/금/토)
    var weekdayCharKo: String {
        let weekday = Calendar.current.component(.weekday, from: self)
        return ["일", "월", "화", "수", "목", "금", "토"][(weekday - 1) % 7]
    }

    /// 언어 설정에 따른 요일 약칭: 영어 "Fri" / 한국어 "금"
    var weekdayString: String {
        let df = DateFormatter()
        if AppLanguage.shared.isEnglish {
            df.locale = Locale(identifier: "en_US")
            df.dateFormat = "EEE"
        } else {
            df.locale = Locale(identifier: "ko_KR")
            df.dateFormat = "EEEEE"
        }
        return df.string(from: self)
    }

    /// "M월 d일" (KO) / "MMM d" (EN) — used on splits share card
    var cardShortDateString: String {
        let df = DateFormatter()
        if AppLanguage.shared.isEnglish {
            df.locale = Locale(identifier: "en_US")
            df.dateFormat = "MMM d"
        } else {
            df.locale = Locale(identifier: "ko_KR")
            df.dateFormat = "M월 d일"
        }
        return df.string(from: self)
    }
}
