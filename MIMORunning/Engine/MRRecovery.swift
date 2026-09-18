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

/// 회복 곡선의 모양. HR(t) = HR∞ + (HRend − HR∞)·e^(−t/τ) 의 1차 지수감쇠 파라미터.
///   Pierpont & Voth 2004 (Am J Cardiol 94(1):64–68).
/// ⚠ `ratio`는 두 낙폭의 비라 종료심박이 소거된다 — HRR1과 달리 강도 보정 회귀가 필요 없다.
/// ⚠ `asymptote`는 2분 외삽이라 불안정하다. 표시하지 않고 디버그로만 쓴다.
struct MRRecoveryDecay: Sendable {
    let ratio: Double      // x = (hr60 − hr120) / (endHR − hr60)
    let tau: Double        // 초
    let asymptote: Double  // HR∞ (bpm)
}

/// 리듬 카드 한 줄에 필요한 값 묶음. 뷰는 이걸 받아 `MRRecovery.shapeCaption`이 만든 문자열만 그린다.
struct MRRecoveryShape: Sendable {
    let hrr1: Double
    let hrr2: Double
    let decay: MRRecoveryDecay
    /// 과거 τ 분포 안에서 이 러닝의 위치(0...1). 표본 8개 미만이면 nil → 비교하지 않는다.
    let percentile: Double?
}

struct MRRecoveryResult: Sendable {
    let endHR: Double          // 종료 직전 30초 평균
    let hr60: Double
    let hr120: Double?
    var hrr1: Double { endHR - hr60 }
    var hrr2: Double? { hr120.map { endHR - $0 } }
    /// 회복 곡선 모양. 120초 샘플이 있고 가드를 통과할 때만 생긴다.
    var decay: MRRecoveryDecay? {
        hr120.flatMap { MRRecovery.decay(endHR: endHR, hr60: hr60, hr120: $0) }
    }
}

extension MRRecoveryShape {
    /// `decay`가 성립할 때만 만들어진다 — hrr2와 decay가 서로 어긋난 상태를 타입이 막는다.
    /// (`decay`는 hr120이 있어야 생기므로 hrr2도 반드시 있다.)
    init?(_ r: MRRecoveryResult, percentile: Double?) {
        guard let d = r.decay, let h2 = r.hrr2 else { return nil }
        self.init(hrr1: r.hrr1, hrr2: h2, decay: d, percentile: percentile)
    }
}

enum MRRecovery {

    static let endWindowSec: TimeInterval = 30       // 임의로 정함 — 종료 직전 평균 창
    static let sampleTolSec: TimeInterval = 15       // 임의로 정함 — t±15초 안 샘플의 중앙값
    static let postWindowSec: TimeInterval = 180     // Apple 피트니스와 같은 3분
    static let minEndHRFracOfMax = 0.80              // 임의로 정함 — 존 3 하한 근처. 70%는 194건 중 193건이 통과해 아무것도 거르지 못했다
    static let minEndHRWhenMaxUnknown = 130.0        // 임의로 정함
    static let minObs = 16                           // 임의로 정함 — 회귀 안정성

    // MARK: 회복 곡선 모양 (τ) — 전부 임의값. 수식이 발산하거나 감쇠가 아닌 경우를 거른다.

    static let minFirstMinuteDrop = 8.0       // 분모가 작으면 x가 발산한다
    static let tauRange: ClosedRange<Double> = 20...300
    // τ 상한 300초 = x ≤ 0.819. 200초(x ≤ 0.741)로 잡으면 "2분 뒤에도 계속 내려오는 중"인
    // 러닝을 판정 전에 가드가 먼저 버린다. 문헌상 최대운동 후 τ는 대체로 30–120초.

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

    /// 세 값으로 τ를 닫힌 해로 구한다. 가드에 걸리면 nil — 카드는 침묵한다.
    static func decay(endHR: Double, hr60: Double, hr120: Double) -> MRRecoveryDecay? {
        let d1 = endHR - hr60      // 1분째 낙폭
        let d2 = hr60 - hr120      // 2분째 낙폭
        guard d1 >= minFirstMinuteDrop, d2 > 0 else { return nil }
        let x = d2 / d1        // d1 ≥ 8, d2 > 0 이므로 x > 0은 보장된다
        guard x < 1 else { return nil }   // x ≥ 1은 감쇠가 아니다 — τ가 음수(x>1)이거나 ±∞(x=1)
        let tau = -60.0 / log(x)
        guard tauRange.contains(tau) else { return nil }
        return MRRecoveryDecay(ratio: x, tau: tau, asymptote: endHR - d1 / (1 - x))
    }

    /// 저장된 히스토리 한 점에서 τ. `hrr1 = endHR − hr60` 이므로 hr60을 되돌려 쓴다 —
    /// 캐시가 hr60을 따로 들지 않아도 되는 이유다.
    static func decay(endHR: Double, hrr1: Double, hr120: Double) -> MRRecoveryDecay? {
        decay(endHR: endHR, hr60: endHR - hrr1, hr120: hr120)
    }

    static let minTauSamples = 8   // 임의로 정함 — 사분위가 의미를 갖는 최소선

    /// 과거 τ 중 오늘보다 작은(= 더 빨랐던) 것의 비율. 표본이 모자라면 nil.
    /// ⚠ `history`에 오늘 러닝을 넣지 않는다 — 자기를 포함하면 표본이 작을수록 가운데로 끌린다.
    static func tauPercentile(_ tau: Double, history: [Double]) -> Double? {
        guard history.count >= minTauSamples else { return nil }
        return Double(history.filter { $0 < tau }.count) / Double(history.count)
    }

    /// 리듬 카드 캡션 둘째 줄.
    /// ⚠ 좋다/나쁘다를 말하지 않는다 — Le Meur 2015(PLOS One 10:e0139754)에서 기능적 과부하 시
    ///   HRR이 오히려 빨라졌다. 빠름 = 좋음으로 읽히면 안 된다.
    /// ⚠ τ의 공인 절단점은 없다. 개인 분포 사분위로만 말한다(§2-3: 기준은 외부 공인 표준).
    /// 과거 τ 표본이 `minTauSamples` 미만이면 nil을 돌려주고 카드는 그 줄을 아예 그리지 않는다 —
    /// 원시 숫자("1분 −38 · 2분 −52bpm") 폴백은 없앴다. 같은 숫자는 상세 화면 심박 패널의
    /// 회복 차트가 이미 보여주고, 있다 없다가 τ 성립 여부(120초 샘플과 무관한 조건)에 갈리는
    /// 줄은 그 이유를 화면이 말해주지 않는 한 아무것도 없는 것보다 못하다(§2-4).
    static func shapeCaption(_ shape: MRRecoveryShape) -> String? {
        let L = AppLanguage.shared
        guard let p = shape.percentile else { return nil }
        // 양끝 다 사분위 포함(<=, >=)으로 대칭을 맞춘다. n=8이면 tauPercentile은 {0, .125, ..., 1.0}
        // 9개 값만 낼 수 있어, 한쪽만 "포함"이면(예: p < 0.25) 그 버킷이 다른 쪽보다 좁아진다
        // (< 0.25 → 2/9, >= 0.75 → 3/9). p == 0.25는 "과거 넷 중 하나가 더 빨랐다"는 하위
        // 사분위의 자연스러운 경계값이라 포함한다. p == 0.75도 대칭으로 포함.
        if p <= 0.25 { return L.s("평소보다 빠르게 안정됐어요", "Settled faster than usual") }
        if p >= 0.75 { return L.s("2분 뒤에도 계속 내려오는 중이었어요", "Still coming down after 2 min") }
        return L.s("평소대로 내려왔어요", "Came down as usual")
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
