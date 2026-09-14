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

    /// 규칙(fa60426 이후): 관측 지표 2개 이상 · 그중 실증 변화 1개 이상이면 말한다. 실증 0개면 침묵.
    /// 실증 = (MDC 초과 ‖ 4주+ 연속) ∧ 실질 크기(케이던스 ≥1spm · 지면접촉 ≥3ms · 그 외 항상).
    @Test func testFormObservationSpeaksWithOneRealMetricAndStaysSilentWithNone() {
        let voMetric  = mrFormMetrics.first { $0.key == "vo" }!
        let cadMetric = mrFormMetrics.first { $0.key == "cadence" }!
        func shift(_ m: MRFormMetric, delta: Double, weeks: Int) -> MRFormShift {
            MRFormShift(metric: m, recentMean: 0, baseMean: 0, delta: delta, mdc: 1.0, weeksConsistent: weeks, r2: nil)
        }
        let realVo  = shift(voMetric,  delta: 2.0, weeks: 4)   // MDC 초과 + 연속 → 강한 실증
        let realCad = shift(cadMetric, delta: 2.0, weeks: 4)
        let weakVo  = shift(voMetric,  delta: 0.5, weeks: 4)   // MDC 미달이지만 4주 연속 → 약한 실증
        let noneVo  = shift(voMetric,  delta: 0.5, weeks: 2)   // 둘 다 미달 → 실증 아님
        let noneCad = shift(cadMetric, delta: 0.5, weeks: 2)   // + 실질 크기(1spm)도 미달

        // 관측 지표 1개뿐 → "달리는 방식" 논거 없음 → 침묵
        #expect(mrFormObservation([realVo]) == nil)
        // 관측 2개 · 실증 0개 → 안정 → 침묵
        #expect(mrFormObservation([noneVo, noneCad]) == nil)
        // 약한 실증 1개로도 말한다(근거에 [약] 표기)
        let weak = mrFormObservation([weakVo, noneCad])
        #expect(weak != nil)
        #expect(weak?.basis.contains("[약]") == true)
        // 강한 실증 1개 · 2개
        #expect(mrFormObservation([realVo, noneVo]) != nil)
        #expect(mrFormObservation([realVo, realCad]) != nil)
        // 14일 이상 공백이 있으면 추세 판단 불가 → 침묵
        #expect(mrFormObservation([realVo, realCad], hasRecentGap: true) == nil)
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
