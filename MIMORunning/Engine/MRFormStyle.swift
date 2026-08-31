import Foundation
import SwiftUI

// MARK: - 설계 원칙
//
// 이 모듈은 "폼이 좋다/나쁘다"를 말하지 않는다. 말할 수 없다.
//   · 실험실 전체 3D 모션캡처로도 러닝 이코노미 상·하위군 분류가 62%다
//     (Van Hooren 2024, Scand J Med Sci Sports 34(3):e14605)
//   · 부상 예측은 n=3,404 메타분석에서 근거가 없다
//     (Peterson 2022, Sports Med Open 8:1)
//   · "수직 진폭이 낮을수록 좋다"는 반대 방향이다 — 숙련자가 더 높았다
//     (Fadillioglu 2022, Bioengineering 9(11):616)
//   · "접지가 짧을수록 좋다"도 반증됐고, 러너 10명 중 9명은
//     이미 자기 최적의 5% 이내에서 달린다 (Moore 2019, Front SAL 1:53)
//
// 대신 **같은 페이스에서 본인이 어떻게 달라졌는지**만 관찰한다.

// MARK: - 데이터 구조

struct MRFormMetric {
    let key: String            // "vo" / "cadence" / "gct"
    let label: String
    let unit: String
    let higherMeansMoreBounce: Bool
}

let mrFormMetrics: [MRFormMetric] = [
    MRFormMetric(key: "vo",      label: "위아래 움직임", unit: "cm",  higherMeansMoreBounce: true),
    MRFormMetric(key: "cadence", label: "케이던스",      unit: "spm", higherMeansMoreBounce: false),
    MRFormMetric(key: "gct",     label: "지면 접촉",     unit: "ms",  higherMeansMoreBounce: false),
]
// ⚠ 보폭은 넣지 않는다. 같은 페이스에서 보폭 = 속도 ÷ 케이던스이므로
//   케이던스 잔차의 정확한 역수다. 같은 정보를 두 번 세는 셈이 된다.

struct MRFormResidual {
    let date: Date
    let value: Double          // 잔차 (실제 − 그 페이스 예상값)
}

struct MRFormShift {
    let metric: MRFormMetric
    let recentMean: Double     // 최근 3개월 잔차 평균
    let baseMean: Double       // 그 이전 3개월 잔차 평균
    let delta: Double
    let mdc: Double            // 최소검출가능변화
    let weeksConsistent: Int
    let r2: Double?            // 잔차 모델 R² — GCT 보정 게이트용
    /// MDC₉₅ 초과 — 통계적으로 유의미한 변화 (강한 근거)
    var isMDCStrong: Bool  { abs(delta) > mdc }
    /// 4주 이상 같은 방향 — 통계적으로는 미달이지만 방향성이 일관 (약한 근거)
    var isConsistent: Bool { weeksConsistent >= 4 }
    /// 실질적 최소 변화량 — 통계 유의성과 별개로 지표 단위에서 의미 있는 크기인지 확인
    var isPractical: Bool {
        switch metric.key {
        case "cadence": return abs(delta) >= 1.0   // 1.0 spm
        case "gct":     return abs(delta) >= 3.0   // 3.0 ms
        default:        return true
        }
    }
    /// 통계적 근거 OR 연속성 근거, AND 실질적 크기 충족
    var isReal: Bool { (isMDCStrong || isConsistent) && isPractical }
}

// 한 워크아웃에서 페이스와 폼 지표를 짝지은 관측값.
// 필터링(야외·비인터벌·20분+·3km+)은 호출 쪽에서 수행한다.
struct MRFormObs {
    let date: Date
    let speedMPerMin: Double
    let metricValue: Double
}

// MARK: - 0. 날짜별 대표 속도 맵

/// 야외·비인터벌·20분+·3km+ 런에서 날짜(startOfDay) → 속도(m/min) 맵을 만든다.
/// 같은 날 런이 여럿이면 더 빠른 쪽을 유지한다 (VO2/폼 메트릭과 고강도 상관).
func mrFormSpeedByDate(_ runs: [MRWorkout]) -> [Date: Double] {
    Dictionary(
        runs.compactMap { r -> (Date, Double)? in
            guard !r.indoor, !r.isInterval,
                  r.durationMin >= 20, (r.distanceKm ?? 0) >= 3,
                  let speed = r.speedMPerMin else { return nil }
            return (r.date, speed)
        },
        uniquingKeysWith: { old, new in max(old, new) }
    )
}

// MARK: - 1. 개인 회귀와 잔차

/// 지표를 본인 페이스에 회귀시키고 잔차를 낸다.
///
/// ⚠ 집단 평균 보정식을 쓰면 안 된다. Zandbergen 2023
///   (Front Sports Act Living 5:1085513)에서 개인 간 속도 계수 편차가
///   매우 컸다(PTA 계수 1.45–7.76). 반드시 개인별 회귀여야 한다.
///
/// ⚠ 인터벌 세션은 뺀다. 질주와 회복의 평균이라 페이스-지표 관계가 깨진다.
func mrFormResiduals(obs: [MRFormObs], asOf: Date) -> [MRFormResidual] {
    let cal = Calendar.current
    let cutoff = cal.startOfDay(for: asOf)
    let valid = obs.filter {
        let d = cal.dateComponents([.day], from: $0.date, to: cutoff).day ?? 999
        return d >= 0 && d <= 365
    }
    #if DEBUG
    if valid.count < 25 {
        print("[폼] 잔차 계산 불가 — 관측값 \(valid.count)개 (최소 25, 입력 \(obs.count)개)")
    } else {
        print("[폼] 잔차 계산 시작 — 관측값 \(valid.count)개")
    }
    #endif
    guard valid.count >= 25 else { return [] }

    // metric ~ 1 + speed + speed²  (관계가 곡선일 수 있다)
    var X: [[Double]] = [], y: [Double] = []
    for o in valid {
        let s = o.speedMPerMin
        X.append([1.0, s, s * s])
        y.append(o.metricValue)
    }
    guard let c = MRLinAlg.lstsq(X: X, y: y) else { return [] }

    return valid.map { o in
        let s = o.speedMPerMin
        let pred = c[0] + c[1] * s + c[2] * s * s
        return MRFormResidual(date: o.date, value: o.metricValue - pred)
    }
}

// MARK: - 2. 변화 판정

/// MDC₉₅ = 1.96 × SD_resid × √(1/n_recent + 1/n_base)
///
/// 본인 잔차 산포에서 직접 구한다 — 기기 오차가 이미 데이터에 반영돼 있으므로.
func mrFormMDC(sd: Double, nRecent: Int, nBase: Int) -> Double {
    1.96 * sd * (1.0/Double(nRecent) + 1.0/Double(nBase)).squareRoot()
}

/// 최근 4주 vs 그 이전 12주의 잔차 평균 차이가 잡음을 넘는가.
///
/// ⚠ MDC를 문헌에서 가져오지 않는다. **본인 잔차 산포에서 직접 잰다.**
///   기기 오차가 얼마든(Apple Watch GCT는 MAPE 19%로 알려져 있다)
///   그 사람 데이터에 이미 반영되어 있으므로 자기교정된다.
///
///   MDC₉₅ = 1.96 × SD_resid × √(1/n_recent + 1/n_base)
func mrFormShift(_ residuals: [MRFormResidual],
                 metric: MRFormMetric,
                 asOf: Date,
                 obs: [MRFormObs] = []) -> MRFormShift? {
    let cal = Calendar.current
    let cutoff = cal.startOfDay(for: asOf)
    func days(_ d: Date) -> Int {
        cal.dateComponents([.day], from: d, to: cutoff).day ?? 999
    }
    let recent = residuals.filter { let x = days($0.date); return x >= 0  && x < 90  }
    let base   = residuals.filter { let x = days($0.date); return x >= 90 && x < 180 }
    #if DEBUG
    let _df = DateFormatter(); _df.dateFormat = "yyyy-MM-dd"
    let _asOfStr = _df.string(from: asOf)
    if recent.count < 20 || base.count < 20 {
        print("[폼] \(metric.key) n부족 — 기준일 \(_asOfStr) · 최근 3개월 \(recent.count)개 최소 20 / 이전 3개월 \(base.count)개 최소 20")
    } else {
        print("[폼] \(metric.key) 잔차 — 기준일 \(_asOfStr) · 최근 3개월 \(recent.count)개 / 이전 3개월 \(base.count)개")
    }
    #endif
    guard recent.count >= 20, base.count >= 20 else { return nil }

    let all = residuals.map(\.value)
    let mean = all.reduce(0, +) / Double(all.count)
    let sd = (all.map { ($0-mean)*($0-mean) }.reduce(0, +) / Double(all.count-1)).squareRoot()

    let rMean = recent.map(\.value).reduce(0, +) / Double(recent.count)
    let bMean = base.map(\.value).reduce(0, +)   / Double(base.count)
    let mdc   = mrFormMDC(sd: sd, nRecent: recent.count, nBase: base.count)

    // 주 단위로 같은 방향이 몇 주 이어졌는지
    // ⚠ 3주로는 부족하다. 8지표 환경에서 "3주 연속"은 90% 확률로 우연히 생긴다.
    var weeks = 0
    let dir = (rMean - bMean) > 0 ? 1.0 : -1.0
    for w in 0..<12 {
        let lo = w * 7, hi = lo + 7
        let seg = residuals.filter { let x = days($0.date); return x >= lo && x < hi }
        guard seg.count >= 1 else { break }
        let m = seg.map(\.value).reduce(0, +) / Double(seg.count)
        if (m - bMean) * dir > 0 { weeks += 1 } else { break }
    }

    // R² — 잔차 모델 설명력. obs 있을 때만 계산. GCT 보정 게이트에 사용.
    var r2: Double? = nil
    if !obs.isEmpty {
        let yVals = obs.filter { let x = days($0.date); return x >= 0 && x <= 365 }.map(\.metricValue)
        if yVals.count == residuals.count, !yVals.isEmpty {
            let ssRes = residuals.map { $0.value * $0.value }.reduce(0, +)
            let yMean = yVals.reduce(0, +) / Double(yVals.count)
            let ssTot = yVals.map { ($0 - yMean) * ($0 - yMean) }.reduce(0, +)
            r2 = ssTot > 0 ? 1.0 - ssRes / ssTot : 0.0
        }
    }
    let shift = MRFormShift(metric: metric, recentMean: rMean, baseMean: bMean,
                            delta: rMean - bMean, mdc: mdc, weeksConsistent: weeks, r2: r2)
    #if DEBUG
    let _mdcOK  = shift.isMDCStrong
    let _wOK    = shift.isConsistent
    let _pracOK = shift.isPractical
    let _pracThreshold: Double = metric.key == "cadence" ? 1.0 : metric.key == "gct" ? 3.0 : 0.0
    let _verdict: String
    switch (_mdcOK, _wOK, _pracOK) {
    case (_, _, false):  _verdict = "미표시 (실질 미달)"
    case (true,  _, _):  _verdict = "강한 추세 (MDC 근거)"
    case (_, true, _):   _verdict = "약한 추세 (연속성 근거)"
    default:             _verdict = "미표시"
    }
    print(String(format: "[폼] %@ 최근%+.2f 이전%+.2f 차%+.2f",
                 metric.key, rMean, bMean, shift.delta))
    print(String(format: "     MDC %.2f %@ | 실질 %.2f≥%.1f %@ | 연속 %d주 %@ (기준 4주)",
                 mdc, _mdcOK ? "✓" : "✗",
                 abs(shift.delta), _pracThreshold, _pracOK ? "✓" : "✗",
                 weeks, _wOK ? "✓" : "✗"))
    print("     → \(shift.isReal ? "표시" : "미표시"): \(_verdict)")
    if let _r2 = r2 {
        print(String(format: "[폼] %@ 잔차 모델 R²=%.3f (기준 0.2 %@)", metric.key, _r2, _r2 >= 0.2 ? "✓" : "✗"))
    }
    #endif
    return shift
}

// MARK: - 3. 문장 생성

/// ⚠ "깡총 뛴다", "비효율적이다", "폼이 나쁘다"는 쓰지 않는다.
///   현상을 그대로 묘사하고, 원인은 후보만 제시하며 단정하지 않는다.
///   그리고 **두 지표가 서로 맞을 때만** 말한다 — 하나만으로는 우연이다.
func mrFormObservation(_ shifts: [MRFormShift], hasRecentGap: Bool = false, refCadence: Int? = nil) -> (text: String, basis: String, isStable: Bool)? {
    let L = AppLanguage.shared
    let real = shifts.filter(\.isReal)
    #if DEBUG
    print("[폼] 관찰 — 실증 지표 \(real.count)/\(shifts.count)개 \(real.map(\.metric.key).joined(separator: "·"))\(hasRecentGap ? " [공백 있음 → 추세 침묵]" : "")")
    if shifts.count >= 2, real.isEmpty { print("[폼] 안정 → 미표시 (실증 0개)") }
    #endif
    // 14일 이상 공백이 있으면 추세 판단 불가 — 공백 전후 데이터가 섞여 변화가 상쇄됨
    guard !hasRecentGap else { return nil }
    // 관측 지표 2개 미만이면 "달리는 방식" 전체 논거 없음
    guard shifts.count >= 2 else { return nil }
    // 실증 변화가 없으면 침묵 — 안정은 기본 상태이므로 말할 필요 없음
    guard real.count >= 1 else { return nil }

    // 최대 2줄까지 표시 — 방향이 반대인 지표가 한 줄에 붙지 않도록 줄바꿈
    let capped = Array(real.prefix(2))

    // 케이던스 + 지면접촉이 함께 뜨면 공중 시간으로 연결한 단일 문장
    // 공중 시간 = (60000 / 케이던스) − 지면접촉 (ms per step)
    if let cs = capped.first(where: { $0.metric.key == "cadence" }),
       let gs = capped.first(where: { $0.metric.key == "gct" }) {
        let cadSpm = Double(refCadence ?? 170)
        let stepTimeDeltaMs = -60_000.0 / (cadSpm * cadSpm) * cs.delta
        let airtimeDeltaMs  = stepTimeDeltaMs - gs.delta
        let airtimeMs = max(1, Int(abs(airtimeDeltaMs).rounded()))
        let cadAbs    = max(1, Int(abs(cs.delta).rounded()))
        let gctAbs    = max(1, Int(abs(gs.delta).rounded()))
        let isStrong  = cs.isMDCStrong || gs.isMDCStrong
        let wks       = max(cs.weeksConsistent, gs.weeksConsistent)
        let durKor    = wks >= 12 ? "3개월째" : wks >= 8 ? "2개월째" : "\(wks)주째"
        let durEng    = wks >= 12 ? "for 3 months" : wks >= 8 ? "for 2 months" : "for \(wks) weeks"
        let timeKor   = isStrong ? " 3개월 새" : " \(durKor)"
        let timeEng   = isStrong ? " over 3 months" : " \(durEng)"
        let cadDirKor = cs.delta < 0 ? "내려가고" : "올라가고"
        let gctDirKor = gs.delta < 0 ? "짧아졌어요." : "길어졌어요."
        let airDirKor   = airtimeDeltaMs > 0 ? "길어졌어요." : "짧아졌어요."
        let strideKor   = airtimeDeltaMs > 0 ? "더 큰 한 걸음으로" : "더 잦은 걸음으로"
        let cadDirEng   = cs.delta < 0 ? "dropped" : "rose"
        let gctDirEng   = gs.delta < 0 ? "shortened" : "lengthened"
        let airDirEng   = airtimeDeltaMs > 0 ? "increased" : "decreased"
        let strideEng   = airtimeDeltaMs > 0 ? "taking longer, bigger strides" : "stepping more frequently with shorter strides"
        let korText = "같은 페이스에서 케이던스가\(timeKor) \(cadAbs)spm \(cadDirKor), 지면접촉이 \(gctAbs)ms \(gctDirKor)\n공중에 머무는 시간이 \(airtimeMs)ms \(airDirKor)\n같은 페이스를 \(strideKor) 만들고 있다는 뜻이에요."
        let engText = "At similar pace, cadence\(timeEng) \(cadDirEng) \(cadAbs) spm, contact \(gctDirEng) \(gctAbs) ms.\nAirtime per step \(airDirEng) ~\(airtimeMs) ms.\nAt the same pace, you're \(strideEng)."
        let text  = L.s(korText, engText)
        let basis = [cs, gs].map { s in
            let strength = s.isMDCStrong ? "강" : "약"
            return L.isEnglish
                ? String(format: "%@ %+.1f%@ [%@] (threshold %.1f · %dw consistent)",
                         s.metric.key, s.delta, s.metric.unit, s.isMDCStrong ? "strong" : "weak", s.mdc, s.weeksConsistent)
                : String(format: "%@ %+.1f%@ [%@] (임계 %.1f · %d주 연속)",
                         s.metric.key, s.delta, s.metric.unit, strength, s.mdc, s.weeksConsistent)
        }.joined(separator: " · ")
        return (text, basis, false)
    }

    // 각 실증 지표마다 2줄 생성
    // · 1줄 = 관찰: "같은 페이스에서 지면접촉이 3개월 새 8ms 짧아졌어요."
    // · 2줄 = 의미: "지면에서 더 빨리 떨어지고 있다는 뜻이에요."
    // ⚠ "같은 페이스에서"를 반드시 넣는다 — 페이스 효과가 아님을 밝히는 근거.
    // ⚠ 메커니즘(근력·탄성·이코노미 등) 주장 금지 — 현상만 서술.
    let korLines: [String] = capped.map { s in
        let gctVal = "\(Int(abs(s.delta).rounded()))ms"
        let cadVal = "\(Int(abs(s.delta).rounded()))spm"
        if s.isMDCStrong {
            switch s.metric.key {
            case "cadence":
                let l1 = s.delta > 0
                    ? "같은 페이스에서 케이던스가 3개월 새 \(cadVal) 올랐어요."
                    : "같은 페이스에서 케이던스가 3개월 새 \(cadVal) 내려갔어요."
                let l2 = s.delta > 0
                    ? "발걸음이 더 잦아지고 있다는 뜻이에요."
                    : "발걸음이 느려지고 있다는 뜻이에요."
                return "\(l1)\n\(l2)"
            case "gct":
                let l1 = s.delta < 0
                    ? "같은 페이스에서 지면접촉이 3개월 새 \(gctVal) 짧아졌어요."
                    : "같은 페이스에서 지면접촉이 3개월 새 \(gctVal) 길어졌어요."
                let l2 = s.delta < 0
                    ? "지면에서 더 빨리 떨어지고 있다는 뜻이에요."
                    : "지면에 더 오래 닿고 있다는 뜻이에요."
                return "\(l1)\n\(l2)"
            default:
                return s.delta > 0 ? "\(s.metric.label)이 3개월 새 증가했어요." : "\(s.metric.label)이 3개월 새 감소했어요."
            }
        } else {
            let dur = s.weeksConsistent >= 12 ? "3개월째"
                    : s.weeksConsistent >= 8  ? "2개월째"
                    : "\(s.weeksConsistent)주째"
            switch s.metric.key {
            case "cadence":
                let l1 = s.delta > 0
                    ? "같은 페이스에서 케이던스가 \(dur) 조금씩 올라가고 있어요."
                    : "같은 페이스에서 케이던스가 \(dur) 조금씩 내려가고 있어요."
                let l2 = s.delta > 0
                    ? "발걸음이 서서히 잦아지는 추세예요."
                    : "발걸음이 서서히 느려지는 추세예요."
                return "\(l1)\n\(l2)"
            case "gct":
                let l1 = s.delta < 0
                    ? "같은 페이스에서 지면접촉이 \(dur) 조금씩 짧아지고 있어요."
                    : "같은 페이스에서 지면접촉이 \(dur) 조금씩 길어지고 있어요."
                let l2 = s.delta < 0
                    ? "지면에서 서서히 더 빨리 떨어지는 추세예요."
                    : "지면에 서서히 더 오래 닿는 추세예요."
                return "\(l1)\n\(l2)"
            default:
                let dir = s.delta > 0 ? "증가하고" : "감소하고"
                return "같은 페이스에서 \(s.metric.label)이 \(dur) 조금씩 \(dir) 있어요."
            }
        }
    }
    let engLines: [String] = capped.map { s in
        let gctVal = "\(Int(abs(s.delta).rounded())) ms"
        let cadVal = "\(Int(abs(s.delta).rounded())) spm"
        if s.isMDCStrong {
            switch s.metric.key {
            case "cadence":
                let l1 = s.delta > 0
                    ? "At similar pace, cadence rose \(cadVal) over 3 months."
                    : "At similar pace, cadence dropped \(cadVal) over 3 months."
                let l2 = s.delta > 0
                    ? "Your stride rate is getting faster."
                    : "Your stride rate is getting slower."
                return "\(l1)\n\(l2)"
            case "gct":
                let l1 = s.delta < 0
                    ? "At similar pace, ground contact shortened \(gctVal) over 3 months."
                    : "At similar pace, ground contact lengthened \(gctVal) over 3 months."
                let l2 = s.delta < 0
                    ? "You're pushing off the ground faster."
                    : "You're spending more time on the ground."
                return "\(l1)\n\(l2)"
            default:
                return s.delta > 0 ? "\(s.metric.label) increased over 3 months." : "\(s.metric.label) decreased over 3 months."
            }
        } else {
            let dur = s.weeksConsistent >= 12 ? "for 3 months"
                    : s.weeksConsistent >= 8  ? "for 2 months"
                    : "for \(s.weeksConsistent) weeks"
            switch s.metric.key {
            case "cadence":
                let l1 = s.delta > 0
                    ? "At similar pace, cadence has been gradually rising \(dur)."
                    : "At similar pace, cadence has been gradually dropping \(dur)."
                let l2 = s.delta > 0
                    ? "Your stride rate is slowly getting faster."
                    : "Your stride rate is slowly getting slower."
                return "\(l1)\n\(l2)"
            case "gct":
                let l1 = s.delta < 0
                    ? "At similar pace, ground contact has been gradually shortening \(dur)."
                    : "At similar pace, ground contact has been gradually lengthening \(dur)."
                let l2 = s.delta < 0
                    ? "A gradual trend of quicker push-off."
                    : "A gradual trend of longer ground contact."
                return "\(l1)\n\(l2)"
            default:
                let dir = s.delta > 0 ? "increasing" : "decreasing"
                return "At similar pace, \(s.metric.label) has been gradually \(dir) \(dur)."
            }
        }
    }
    let text = L.s(
        korLines.joined(separator: "\n"),
        engLines.joined(separator: "\n")
    )

    let basis = capped.map { s in
        let strength = s.isMDCStrong ? "강" : "약"
        return L.isEnglish
            ? String(format: "%@ %+.1f%@ [%@] (threshold %.1f · %dw consistent)",
                     s.metric.key, s.delta, s.metric.unit, s.isMDCStrong ? "strong" : "weak", s.mdc, s.weeksConsistent)
            : String(format: "%@ %+.1f%@ [%@] (임계 %.1f · %d주 연속)",
                     s.metric.key, s.delta, s.metric.unit, strength, s.mdc, s.weeksConsistent)
    }.joined(separator: " · ")

    return (text, basis, false)
}

// MARK: - 4. 카드 뷰

struct MRFormObservationCard: View {
    let text: String
    let basis: String
    var isStable: Bool = false   // true → "달리는 방식", false → "달리기 스타일 변화"

    @State private var expanded = false

    var body: some View {
        let L = AppLanguage.shared
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "figure.run.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mrInk3)
                Text(isStable ? L.s("달리는 방식", "Running Style") : L.s("달리기 스타일 변화", "Running Style Shift"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Text(expanded ? L.s("접기", "Collapse") : L.s("근거", "Basis"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.violet)
                }
                .buttonStyle(.plain)
            }
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.mrInk2)
                .fixedSize(horizontal: false, vertical: true)
            if expanded {
                Text(basis)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.mrInk3)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
