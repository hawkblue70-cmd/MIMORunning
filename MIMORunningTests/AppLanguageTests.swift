import Testing
import Foundation
@testable import MIMORunning

/// 세 언어(한국어·영어·일본어) 문구 고르기 — 일본어 번역이 없으면 영어로 대체.
@Suite("AppLanguage 언어 고르기")
struct AppLanguageTests {

    private let L = AppLanguage.shared

    @Test("한국어는 한국어 문구", .korean)
    func korean() {
        #expect(L.s("기록", "Activities", ja: "記録") == "기록")
        #expect(!L.isEnglish)
        #expect(!L.isJapanese)
    }

    @Test("영어는 영어 문구", .english)
    func english() {
        #expect(L.s("기록", "Activities", ja: "記録") == "Activities")
        #expect(L.isEnglish)
        #expect(!L.isJapanese)
    }

    @Test("일본어는 일본어 문구, 번역이 없으면 영어", .japanese)
    func japanese() {
        #expect(L.s("기록", "Activities", ja: "記録") == "記録")
        #expect(L.s("기록", "Activities") == "Activities")
        // 아직 일본어 갈래가 없는 isEnglish 분기는 영어 쪽으로 간다
        #expect(L.isEnglish)
        #expect(L.isJapanese)
    }

    @Test("로케일은 언어를 따른다")
    func locale() {
        #expect(inKorean { L.locale.identifier } == "ko_KR")
        #expect(inEnglish { L.locale.identifier } == "en_US")
        #expect(inJapanese { L.locale.identifier } == "ja_JP")
    }

    @Test("일본어 날짜 형식")
    func japaneseDates() {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 3; c.hour = 18; c.minute = 5
        let d = Calendar.current.date(from: c)!
        inJapanese {
            #expect(d.cardDateString == "2026年10月3日")
            #expect(d.cardShortDateString == "10月3日")
            #expect(d.cardTimeString == "18:05")
            #expect(d.weekdayString == "土")
        }
    }
}
