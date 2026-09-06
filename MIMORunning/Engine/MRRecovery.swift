import Foundation

// MARK: - 운동 후 심박 회복 (HRR)
//
// HRR1 = 종료 심박 − 종료 60초 후 심박. 훈련 상태가 좋아지면 커진다.
//   Daanen 2012 (Int J Sports Physiol Perform 7(3):251–260, 체계적 문헌고찰).
// ⚠ 같은 리뷰가 강조하듯 종료 직전 강도와 쿨다운 행동(걷기·서기)에 크게 좌우된다.
//   → 러닝 간 절대값 비교 금지. 종료 심박을 회귀로 통제한 개인 추세만 말한다.
// ⚠ 임상 절단점(Cole 1999 "12bpm 이하")은 트레드밀 검사 기준이라 쓰지 않는다.
// ⚠ 하루 단위 컨디션·피로 판정에는 쓰지 않는다 — 과훈련 시 빨라진다/느려진다 보고가 갈린다.

/// 종료 시각 기준 초 오프셋의 심박 샘플.
struct MRRecoveryPoint: Codable, Sendable {
    let offset: TimeInterval   // 워크아웃 종료 후 경과 초 (≥ 0)
    let bpm: Int
}

struct MRRecoveryResult: Sendable {
    let endHR: Double          // 종료 직전 30초 평균
    let hr60: Double
    let hr120: Double?
    var hrr1: Double { endHR - hr60 }
    var hrr2: Double? { hr120.map { endHR - $0 } }
}

enum MRRecovery {

    static let endWindowSec: TimeInterval = 30       // 임의로 정함 — 종료 직전 평균 창
    static let sampleTolSec: TimeInterval = 15       // 임의로 정함 — t±15초 안 샘플의 중앙값
    static let postWindowSec: TimeInterval = 180     // Apple 피트니스와 같은 3분
    static let minEndHRFracOfMax = 0.80              // 임의로 정함 — 존 3 하한 근처. 70%는 194건 중 193건이 통과해 아무것도 거르지 못했다
    static let minEndHRWhenMaxUnknown = 130.0        // 임의로 정함
    static let minObs = 16                           // 임의로 정함 — 회귀 안정성

    // MARK: 종료 심박

    /// 워크아웃 내부 시계열(시작 기준 오프셋)에서 마지막 30초 평균. 샘플 없으면 nil.
    static func endHR(series: [(offset: TimeInterval, bpm: Int)], duration: TimeInterval) -> Double? {
        let lo = duration - endWindowSec
        let v = series.filter { $0.offset >= lo && $0.offset <= duration }.map { Double($0.bpm) }
        guard !v.isEmpty else { return nil }
        return v.reduce(0, +) / Double(v.count)
    }

    /// 종료 후 t초 시점 심박 — |offset − t| ≤ 15초 샘플의 중앙값. 없으면 nil.
    static func hr(at t: TimeInterval, post: [MRRecoveryPoint]) -> Double? {
        let v = post.filter { abs($0.offset - t) <= sampleTolSec }.map { Double($0.bpm) }.sorted()
        guard !v.isEmpty else { return nil }
        let n = v.count
        return n % 2 == 0 ? (v[n / 2 - 1] + v[n / 2]) / 2 : v[n / 2]
    }

    /// 표시·집계 자격. 최대심박을 알면 80%, 모르면 130bpm.
    static func isEligible(endHR: Double, maxHR: Double?) -> Bool {
        if let m = maxHR, m > 0 { return endHR >= m * minEndHRFracOfMax }
        return endHR >= minEndHRWhenMaxUnknown
    }

    /// 60초 값이 있어야 결과가 성립한다. 120초는 있으면 덤.
    static func compute(endHR: Double, post: [MRRecoveryPoint]) -> MRRecoveryResult? {
        guard let h60 = hr(at: 60, post: post) else { return nil }
        return MRRecoveryResult(endHR: endHR, hr60: h60, hr120: hr(at: 120, post: post))
    }

    // MARK: 추세

    struct Obs: Sendable {
        let date: Date
        let endHR: Double
        let hrr1: Double
        /// 워크아웃 기온(°C). 더위에서는 심박이 천천히 내려온다 — 여름/봄 비교가 체력 변화로 읽히는 것을 막는다.
        var tempC: Double? = nil
    }

    /// 폼 모듈과 같은 판정기(mrFormShift)를 쓰기 위한 지표 정의.
    static let metric = MRFormMetric(key: "hrr1", label: "1분 회복", unit: "bpm", higherMeansMoreBounce: false)

    /// HRR1 ~ 1 + 종료심박 (+ 기온) — 개인별 선형 최소자승. 최근 365일, 16개 이상.
    /// 종료 심박이 높을수록, 기온이 낮을수록 HRR1이 커지는 효과를 빼서 남는 것(잔차)만 시간에 따라 비교한다.
    /// `useTemp`가 true면 기온 있는 관측만 쓴다(없는 러닝은 그 러닝만 제외). 기온 있는 관측이 16개 미만이면 종료심박만으로 돌아간다.
    static func residuals(obs: [Obs], asOf: Date, useTemp: Bool = true) -> [MRFormResidual] {
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: asOf)
        let inWindow = obs.filter {
            let d = cal.dateComponents([.day], from: $0.date, to: cutoff).day ?? 999
            return d >= 0 && d <= 365
        }
        let withTemp = inWindow.filter { $0.tempC != nil }
        let tempModel = useTemp && withTemp.count >= minObs
        let valid = tempModel ? withTemp : inWindow
        guard valid.count >= minObs else { return [] }
        var X: [[Double]] = [], y: [Double] = []
        for o in valid {
            X.append(tempModel ? [1.0, o.endHR, o.tempC ?? 0] : [1.0, o.endHR])
            y.append(o.hrr1)
        }
        guard let c = MRLinAlg.lstsq(X: X, y: y) else { return [] }
        return valid.map { o in
            let pred = tempModel ? c[0] + c[1] * o.endHR + c[2] * (o.tempC ?? 0) : c[0] + c[1] * o.endHR
            return MRFormResidual(date: cal.startOfDay(for: o.date), value: o.hrr1 - pred)
        }
    }

    /// 좋아진 쪽만 말한다. 나빠진 쪽은 침묵 — 레벨 하락과 같은 태도.
    static func observation(shift: MRFormShift) -> (text: String, basis: String)? {
        guard shift.metric.key == metric.key, shift.isReal, shift.delta > 0 else { return nil }
        let L = AppLanguage.shared
        let d = Int(shift.delta.rounded())
        let text = L.isEnglish
            ? "In runs finished at the same heart rate, your 1-minute recovery improved by \(d) bpm over 3 months."
            : "같은 심박으로 끝낸 러닝에서 1분 회복이 3개월 새 \(d)bpm 늘었어요."
        let basis = String(format: "잔차 Δ%+.1fbpm · MDC %.1f · Daanen 2012", shift.delta, shift.mdc)
        return (text, basis)
    }
}
