import Foundation

// MARK: - App Language

@Observable final class AppLanguage {
    static let shared = AppLanguage()

    /// 앱이 지원하는 언어. `rawValue`는 캐시 키·저장값으로 쓴다.
    enum Lang: String, CaseIterable, Sendable {
        case ko, en, ja

        /// 언어 고르기 화면에 쓰는 이름 — 각 언어로 적는다.
        var nativeName: String {
            switch self {
            case .ko: "한국어"
            case .en: "English"
            case .ja: "日本語"
            }
        }

        /// 날짜·숫자 포맷용 로케일 식별자.
        var localeIdentifier: String {
            switch self {
            case .ko: "ko_KR"
            case .en: "en_US"
            case .ja: "ja_JP"
            }
        }
    }

    /// 테스트 전용 태스크 로컬 오버라이드 — `nil`=앱 설정(`stored`).
    /// 스위프트 테스팅 스위트가 병렬로 돌 때 한 스위트의 언어 전환이 다른 스위트로 새지 않도록,
    /// 전역 값을 쓰지 않고 현재 태스크 트리에만 언어를 묶는다. 앱 코드에서는 항상 `nil`.
    @TaskLocal static var override: Lang? = nil

    private static let storageKey = "appLanguage"
    /// 일본어 추가 전(한국어·영어 두 가지일 때) 쓰던 키 — 첫 실행 때 한 번 옮긴다.
    private static let legacyEnglishKey = "appLanguageIsEnglish"

    /// 사용자가 고른 언어(앱 설정). UserDefaults `appLanguage`와 동기화.
    private var stored: Lang {
        didSet { UserDefaults.standard.set(stored.rawValue, forKey: Self.storageKey) }
    }

    /// 지금 이 문맥에서 유효한 언어 — 모든 읽기는 여기를 거친다(`s(_:_:ja:)`, 날짜 포맷, 엔진·뷰 전부).
    /// 읽기: 태스크 로컬 오버라이드가 있으면 그것, 없으면 저장된 설정. 쓰기: 저장된 설정(UserDefaults)만 바꾼다.
    var current: Lang {
        get { Self.override ?? stored }
        set { stored = newValue }
    }

    /// 한국어가 아닌가 — 일본어도 `true`.
    /// 아직 일본어 갈래가 없는 `if isEnglish { 영어 } else { 한국어 }` 코드가 일본어 사용자에게
    /// 한국어 대신 영어를 보여 주도록 한다(`s(_:_:ja:)`의 영어 대체와 같은 규칙).
    /// 영어와 일본어를 따로 다뤄야 하면 `current`로 갈라 쓴다.
    var isEnglish: Bool { current != .ko }

    /// 일본어인가.
    var isJapanese: Bool { current == .ja }

    /// 지금 언어의 날짜·숫자 포맷용 로케일.
    var locale: Locale { Locale(identifier: current.localeIdentifier) }

    private init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Self.storageKey), let lang = Lang(rawValue: raw) {
            stored = lang
        } else {
            stored = defaults.bool(forKey: Self.legacyEnglishKey) ? .en : .ko
            defaults.set(stored.rawValue, forKey: Self.storageKey)
        }
    }

    /// 지금 언어의 문구를 고른다. 일본어 번역(`ja`)이 없으면 영어를 보여 준다.
    func s(_ ko: String, _ en: String, ja: String? = nil) -> String {
        switch current {
        case .ko: ko
        case .en: en
        case .ja: ja ?? en
        }
    }
}

// MARK: - Date helpers for share cards

extension Date {
    /// 지금 언어의 로케일과 언어별 형식으로 포맷한다.
    private func languageFormatted(ko: String, en: String, ja: String) -> String {
        let L = AppLanguage.shared
        let df = DateFormatter()
        df.locale = L.locale
        df.dateFormat = L.s(ko, en, ja: ja)
        return df.string(from: self)
    }

    /// "yyyy. M. d  a h:mm" (KO) / "MMM d, yyyy  h:mm a" (EN) / "yyyy年M月d日  H:mm" (JA)
    var cardDateTimeString: String {
        languageFormatted(ko: "yyyy. M. d  a h:mm", en: "MMM d, yyyy  h:mm a", ja: "yyyy年M月d日  H:mm")
    }

    /// "yyyy. M. d" (KO) / "MMM d, yyyy" (EN) / "yyyy年M月d日" (JA)
    var cardDateString: String {
        languageFormatted(ko: "yyyy. M. d", en: "MMM d, yyyy", ja: "yyyy年M月d日")
    }

    /// "a h:mm" (KO) / "h:mm a" (EN) / "H:mm" (JA)
    var cardTimeString: String {
        languageFormatted(ko: "a h:mm", en: "h:mm a", ja: "H:mm")
    }

    /// 요일 한자 (일/월/화/수/목/금/토)
    var weekdayCharKo: String {
        let weekday = Calendar.current.component(.weekday, from: self)
        return ["일", "월", "화", "수", "목", "금", "토"][(weekday - 1) % 7]
    }

    /// 언어 설정에 따른 요일 약칭: 영어 "Fri" / 한국어 "금" / 일본어 "金"
    var weekdayString: String {
        languageFormatted(ko: "EEEEE", en: "EEE", ja: "EEEEE")
    }

    /// "M월 d일" (KO) / "MMM d" (EN) / "M月d日" (JA) — used on splits share card
    var cardShortDateString: String {
        languageFormatted(ko: "M월 d일", en: "MMM d", ja: "M月d日")
    }
}
