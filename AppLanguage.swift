import Foundation

// MARK: - App Language

@Observable final class AppLanguage {
    static let shared = AppLanguage()

    /// 테스트 전용 언어 주입. 태스크 로컬이라 병렬로 도는 테스트끼리 서로의 언어를 덮어쓰지 않는다.
    /// 프로덕션에서는 항상 nil이라 저장된 설정이 그대로 쓰인다.
    @TaskLocal static var override: Bool?

    private var storedIsEnglish: Bool {
        didSet { UserDefaults.standard.set(storedIsEnglish, forKey: "appLanguageIsEnglish") }
    }

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
