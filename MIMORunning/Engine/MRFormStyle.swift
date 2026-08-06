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
    let recentMean: Double     // 최근 4주 잔차 평균
    let baseMean: Double       // 그 이전 12주 잔차 평균
    let delta: Double
    let mdc: Double            // 최소검출가능변화
    let weeksConsistent: Int
    var isReal: Bool { abs(delta) > mdc && weeksConsistent >= 4 }
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
                 asOf: Date) -> MRFormShift? {
    let cal = Calendar.current
    let cutoff = cal.startOfDay(for: asOf)
    func days(_ d: Date) -> Int {
        cal.dateComponents([.day], from: d, to: cutoff).day ?? 999
    }
    let recent = residuals.filter { let x = days($0.date); return x >= 0  && x < 28  }
    let base   = residuals.filter { let x = days($0.date); return x >= 28 && x < 112 }
    #if DEBUG
    if recent.count < 6 || base.count < 12 {
        print("[폼] \(metric.key) n부족 (최근 4주 \(recent.count)런 최소 6, 이전 12주 \(base.count)런 최소 12)")
    }
    #endif
    guard recent.count >= 6, base.count >= 12 else { return nil }

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

    let shift = MRFormShift(metric: metric, recentMean: rMean, baseMean: bMean,
                            delta: rMean - bMean, mdc: mdc, weeksConsistent: weeks)
    #if DEBUG
    let flag = shift.isReal ? "✓" : "✗"
    print(String(format: "[폼] %@ resid최근 %+.2f 이전 %+.2f 차 %+.2f MDC %.2f 연속%d주 %@",
                 metric.key, rMean, bMean, shift.delta, mdc, weeks, flag))
    #endif
    return shift
}

// MARK: - 3. 문장 생성

/// ⚠ "깡총 뛴다", "비효율적이다", "폼이 나쁘다"는 쓰지 않는다.
///   현상을 그대로 묘사하고, 원인은 후보만 제시하며 단정하지 않는다.
///   그리고 **두 지표가 서로 맞을 때만** 말한다 — 하나만으로는 우연이다.
func mrFormObservation(_ shifts: [MRFormShift]) -> (text: String, basis: String, isStable: Bool)? {
    let real = shifts.filter(\.isReal)
    #if DEBUG
    print("[폼] 관찰 — 실증 지표 \(real.count)/\(shifts.count)개 \(real.map(\.metric.key).joined(separator: "·"))")
    #endif

    // ★ 안정 분기: 세 지표 모두 데이터가 충분한데 변화량이 모두 측정 오차 범위 안
    //   "상태"이므로 조건 충족 시 항상 표시 — 신선도 게이트 없음.
    if shifts.count == 3, real.isEmpty {
        #if DEBUG
        print("[폼] 안정 → 표시")
        #endif
        let stableText = "지난 3개월, 같은 페이스에서 달리는 방식이 거의 그대로예요.\n"
                       + "흔들림 없이 자리 잡았다는 뜻입니다.\n"
                       + "어느 쪽이 더 좋다는 뜻은 아니에요. "
                       + "달리는 방식은 사람마다 다르고, "
                       + "연구에서도 어떤 형태가 더 경제적이라는 결론은 나오지 않았습니다."
        return (
            text:     stableText,
            basis:    "수직 진폭·케이던스·접지 시간이 모두 측정 오차 범위 안",
            isStable: true
        )
    }

    guard real.count >= 2 else {
        #if DEBUG
        print("[폼] → 침묵 (실증 \(real.count)개 < 2)")
        #endif
        return nil
    }

    let vo  = real.first { $0.metric.key == "vo" }
    let cad = real.first { $0.metric.key == "cadence" }
    let gct = real.first { $0.metric.key == "gct" }

    let disclaimer = "\n어느 쪽이 더 좋다는 뜻은 아니에요. "
                   + "달리는 방식은 사람마다 다르고, "
                   + "연구에서도 어떤 형태가 더 경제적이라는 결론은 나오지 않았습니다."

    var text: String? = nil

    // ① vo↑ & cadence↑
    if let v = vo, v.delta > 0, let c = cad, c.delta > 0 {
        text = "같은 페이스인데 위아래 움직임이 커지고 걸음이 잦아졌어요.\n"
             + "피로가 쌓였을 때, 신발을 바꿨을 때, 노면이 달라졌을 때 "
             + "이런 모양이 나옵니다."
    }
    // ② gct↑ & cadence↓
    else if let g = gct, g.delta > 0, let c = cad, c.delta < 0 {
        text = "같은 페이스에서 발이 땅에 닿아 있는 시간이 길어졌어요.\n"
             + "다리가 무거운 시기에 자주 보이는 모양입니다."
    }
    // ③ vo↓ & gct↓
    else if let v = vo, v.delta < 0, let g = gct, g.delta < 0 {
        text = "같은 페이스에서 위아래 움직임과 접지 시간이 함께 줄었어요.\n"
             + "몸이 그 속도를 다르게 다루기 시작했다는 뜻입니다."
    }
    // ④ cadence↑ & gct↓
    else if let c = cad, c.delta > 0, let g = gct, g.delta < 0 {
        text = "같은 페이스에서 걸음이 잦아지고 접지가 짧아졌어요.\n"
             + "구르는 방식이 바뀌는 중입니다."
    }
    guard let t = text else { return nil }

    let body = t + disclaimer
    let basis = real.map {
        String(format: "%@ %+.1f%@ (임계 %.1f · %d주 연속)",
               $0.metric.label, $0.delta, $0.metric.unit, $0.mdc, $0.weeksConsistent)
    }.joined(separator: " · ")

    return (body, basis, false)
}

// MARK: - 4. 카드 뷰

struct MRFormObservationCard: View {
    let text: String
    let basis: String
    var isStable: Bool = false   // true → "달리는 방식", false → "달리기 스타일 변화"

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "figure.run.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mrInk3)
                Text(isStable ? "달리는 방식" : "달리기 스타일 변화")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Text(expanded ? "접기" : "근거")
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
