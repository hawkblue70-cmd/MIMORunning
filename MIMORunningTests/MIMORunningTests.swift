import Testing
import Foundation
@testable import MIMORunning

// MARK: - 폼 지표 테스트

@Suite("MRFormStyle 핵심 로직")
struct MRFormTests {

    // MDC₉₅ = 1.96 × SD × √(1/n_recent + 1/n_base)
    @Test func testFormMDCFormula() {
        // SD=1.0, n1=10, n2=20 → 1.96 × √(0.1+0.05) = 1.96 × 0.38730 = 0.7591
        #expect(abs(mrFormMDC(sd: 1.0, nRecent: 10, nBase: 20) - 0.7591) < 0.001)
        // SD=2.0, n1=6, n2=12 → 1.96 × 2 × √(0.1667+0.0833) = 1.96 × 2 × 0.5 = 1.96
        #expect(abs(mrFormMDC(sd: 2.0, nRecent: 6, nBase: 12) - 1.96) < 0.001)
    }

    @Test func testFormResidualsRejectsEmptyInput() {
        // 관측값 0개 → 잔차 없음 (최소 25개 미달)
        let result = mrFormResiduals(obs: [], asOf: Date())
        #expect(result.isEmpty)
    }

    /// 문장 게이트는 두 단계다 — 관측 지표 2개 이상 + 그중 실증 변화 1개 이상.
    /// 두 지표가 서로 같은 이야기를 할 필요는 없다.
    @Test func testFormObservationNeedsTwoObservedAndOneRealMetric() {
        let voMetric  = mrFormMetrics.first { $0.key == "vo" }!
        let cadMetric = mrFormMetrics.first { $0.key == "cadence" }!

        // isReal = (MDC 초과 || 4주 이상 일관) && 실질 크기 충족
        let realVo  = MRFormShift(metric: voMetric,  recentMean: 0, baseMean: 0,
                                  delta: 2.0, mdc: 1.0, weeksConsistent: 4, r2: nil)
        let realCad = MRFormShift(metric: cadMetric, recentMean: 0, baseMean: 0,
                                  delta: 2.0, mdc: 1.0, weeksConsistent: 4, r2: nil)
        // MDC 미달 + 4주 미만 → 근거 없음
        let weakVo  = MRFormShift(metric: voMetric,  recentMean: 0, baseMean: 0,
                                  delta: 0.5, mdc: 1.0, weeksConsistent: 3, r2: nil)
        // 케이던스는 1.0spm 미만이면 실질 크기 미달 → MDC를 넘어도 실증 아님
        let weakCad = MRFormShift(metric: cadMetric, recentMean: 0, baseMean: 0,
                                  delta: 0.5, mdc: 0.1, weeksConsistent: 8, r2: nil)

        #expect(realVo.isReal)
        #expect(realCad.isReal)
        #expect(!weakVo.isReal)
        #expect(!weakCad.isReal)

        // 관측 지표가 1개뿐이면 "달리는 방식" 논거가 없다 → 침묵
        #expect(mrFormObservation([realVo]) == nil)
        // 관측 2개여도 실증 변화가 0개면 침묵 — 안정은 기본 상태
        #expect(mrFormObservation([weakVo, weakCad]) == nil)
        // 관측 2개 + 실증 1개 → 그 지표만 놓고 말한다
        #expect(mrFormObservation([realVo, weakCad]) != nil)
        // 실증 2개 (vo↑ & cadence↑) → 물론 말한다
        #expect(mrFormObservation([realVo, realCad]) != nil)
    }
}

// MARK: - 파생 캐시 키 버전 고정 테스트
//
// m3_ 로 올릴 때 이 파일만 뒤처지는 것을 막는다.
// ⌘U 에서 실패하면 해당 캐시 파일도 함께 업데이트해야 한다.

@Suite("캐시 파일명이 MRModelVersion.prefix 로 시작하는지 확인")
struct CacheVersionPrefixTests {

    let expectedPrefix = MRModelVersion.prefix   // "m{N}_"

    @Test func driftCacheFileName() {
        #expect(MRDriftCacheStore.cacheFileName.hasPrefix(expectedPrefix),
                "MRDriftCacheStore.cacheFileName 이 \(expectedPrefix) 로 시작하지 않음")
    }

    @Test func backtestCacheFileName() {
        #expect(MRBacktestCacheStore.cacheFileName.hasPrefix(expectedPrefix),
                "MRBacktestCacheStore.cacheFileName 이 \(expectedPrefix) 로 시작하지 않음")
    }

    @Test func insightCacheFileName() {
        let id = UUID()
        let name = InsightCache.cacheFileName(activityID: id, isRefined: false, language: "ko")
        #expect(name.hasPrefix(expectedPrefix),
                "InsightCache.cacheFileName 이 \(expectedPrefix) 로 시작하지 않음")
    }

    @Test func prefixMatchesCurrent() {
        // prefix = "m{current}_" 형식인지 검증
        let expected = "m\(MRModelVersion.current)_"
        #expect(MRModelVersion.prefix == expected,
                "prefix(\(MRModelVersion.prefix)) 와 current(\(MRModelVersion.current)) 가 어긋남")
    }
}
