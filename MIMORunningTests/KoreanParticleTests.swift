import Testing
@testable import MIMORunning

/// 숫자 뒤 "은/는" 조사 — 마지막 자릿수의 읽는 소리(받침) 기준.
@Suite("KoreanParticle 숫자 뒤 조사")
struct KoreanParticleTests {

    @Test func vowelEndingDigitsTakeNeun() {
        // 2(이)·4(사)·5(오)·9(구) → 받침 없음
        #expect(KoreanParticle.topic(after: "48.5") == "는")
        #expect(KoreanParticle.topic(after: "52") == "는")
        #expect(KoreanParticle.topic(after: "44") == "는")
        #expect(KoreanParticle.topic(after: "39") == "는")
    }

    @Test func consonantEndingDigitsTakeEun() {
        // 1(일)·3(삼)·6(육)·7(칠)·8(팔) → 받침 있음
        #expect(KoreanParticle.topic(after: "41") == "은")
        #expect(KoreanParticle.topic(after: "33") == "은")
        #expect(KoreanParticle.topic(after: "46.6") == "은")
        #expect(KoreanParticle.topic(after: "37") == "은")
        #expect(KoreanParticle.topic(after: "48") == "은")
    }

    @Test func zeroReadsAsYeongOrGongSoTakesEun() {
        #expect(KoreanParticle.topic(after: "50") == "은")
        #expect(KoreanParticle.topic(after: "50.0") == "은")
    }

    @Test func lastDigitDecidesEvenWithTrailingUnitOrNoDigit() {
        // 단위가 붙어도 마지막 숫자 기준
        #expect(KoreanParticle.topic(after: "48.5%") == "는")
        #expect(KoreanParticle.topic(after: "41ms") == "은")
        // 숫자가 없으면 기본 "는"
        #expect(KoreanParticle.topic(after: "") == "는")
    }
}
