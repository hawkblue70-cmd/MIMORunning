import Foundation

// MARK: - 포인트 훈련 (설계: docs/superpowers/specs/2026-09-29-plan-point-session-design.md)
//
// 한 주에 한 번, 강도를 의도적으로 올리는 날. 나머지는 이지.
// 강도 분리 자체의 근거: Stöggl & Sperlich 2014 (Front Physiol 5:33) — 9주 양극화 훈련이
//   역치 위주·고강도 위주·볼륨 위주보다 향상이 컸다.
// ⚠ 단계별 종류 배정·회수·거리는 코칭 관행이다. 통제 연구로 정해진 값이 아니다.
//   인터벌 빠른 구간 ≤ 주간 8% · 역치 구간 ≤ 주간 10%는 Daniels' Running Formula의 관행.

struct MRPlanPoint: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case speed, tempo, buildUp, racePaceShort }

    let kind: Kind
    /// 워밍업·쿨다운 포함 총 거리
    let totalKm: Double
    /// speed · racePaceShort 반복 횟수
    let reps: Int?
    /// 반복 1회 거리 (1.0)
    let repKm: Double?
    /// tempo 지속 거리 · buildUp 마지막 3분의 1
    let sustainedKm: Double?
    /// 빠른 구간 페이스 (초/km) — 예측 기록 기준, 기온 보정 전
    let paceSecPerKm: Double

    static let warmupKm = 2.0
    static let cooldownKm = 1.0
    /// 반복 사이 2분 조깅·400m — ⚠ 임의로 정함
    static let jogBetweenKm = 0.4

    /// 포인트로 세는 앱 저장 유형 — 고강도 판정(`RunSummaryBuilder.isHardRun`)의 종류 규칙과 같다.
    static let pointWorkoutTypes: Set<WorkoutType> = [.interval, .tempo, .buildUp, .distanceRun, .race]

    /// 종류와 이번 주 주간·롱런으로 양을 정한다. 만들 수 없으면 nil(페이스 없음·빌드업이 5km 미만).
    static func make(kind: Kind, weeklyKm: Double, longRunKm: Double,
                     raceDistanceM: Double?, paceSecPerKm: Double) -> MRPlanPoint? {
        guard paceSecPerKm > 0 else { return nil }
        func r1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
        switch kind {
        case .speed:
            let reps = min(max(Int((weeklyKm * 0.08).rounded()), 3), 6)
            let total = warmupKm + Double(reps) + Double(reps - 1) * jogBetweenKm + cooldownKm
            return MRPlanPoint(kind: .speed, totalKm: r1(total), reps: reps, repKm: 1.0,
                               sustainedKm: nil, paceSecPerKm: paceSecPerKm)
        case .tempo:
            let t = Double(min(max(Int((weeklyKm * 0.10).rounded()), 3), 8))
            return MRPlanPoint(kind: .tempo, totalKm: r1(warmupKm + t + cooldownKm), reps: nil, repKm: nil,
                               sustainedKm: t, paceSecPerKm: paceSecPerKm)
        case .buildUp:
            // ⚠ 임의로 정함 — 10K 이하 8km · 하프 10km · 풀 14km · 대회 없음 10km, 롱런의 70% 이하
            let base: Double
            if let d = raceDistanceM {
                base = d >= MRDistance.dF ? 14 : (d >= MRDistance.dH ? 10 : 8)
            } else {
                base = 10
            }
            let b = min(base, (longRunKm * 0.7).rounded(.down))
            guard b >= 5 else { return nil }
            return MRPlanPoint(kind: .buildUp, totalKm: b, reps: nil, repKm: nil,
                               sustainedKm: r1(b / 3), paceSecPerKm: paceSecPerKm)
        case .racePaceShort:
            let total = warmupKm + 3 + 2 * jogBetweenKm + cooldownKm
            return MRPlanPoint(kind: .racePaceShort, totalKm: r1(total), reps: 3, repKm: 1.0,
                               sustainedKm: nil, paceSecPerKm: paceSecPerKm)
        }
    }

    /// 대회 없을 때 번갈이 — 속도 → 템포 → 빌드업 → 속도. 지난 포인트를 모르면 빌드업(가장 부담이 적다).
    static func nextKind(after last: WorkoutType?) -> Kind {
        switch last {
        case .interval: return .tempo
        case .tempo: return .buildUp
        case .buildUp, .distanceRun: return .speed
        default: return .buildUp
        }
    }

    /// 주차표·아침 제안 공용 문구 — "속도 1km × 4회 5'05\"".
    var text: String {
        let L = AppLanguage.shared
        let pace = mrFormatPace(paceSecPerKm)
        switch kind {
        case .speed:
            let n = reps ?? 0
            return L.s("속도 1km × \(n)회 \(pace)", "Speed 1km × \(n) at \(pace)")
        case .tempo:
            let t = mrPointKmString(sustainedKm ?? 0)
            return L.s("템포 \(t)km \(pace)", "Tempo \(t)km at \(pace)")
        case .buildUp:
            let b = mrPointKmString(totalKm), s = mrPointKmString(sustainedKm ?? 0)
            return L.s("빌드업 \(b)km · 마지막 \(s)km \(pace)", "Build-up \(b)km · last \(s)km at \(pace)")
        case .racePaceShort:
            let n = reps ?? 0
            return L.s("대회 페이스 1km × \(n)회 \(pace)", "Race pace 1km × \(n) at \(pace)")
        }
    }
}

/// km 표기 — 정수면 "8", 아니면 "6.4". 계획 문구(eachStr)와 같은 규칙.
func mrPointKmString(_ km: Double) -> String {
    km == km.rounded() ? String(format: "%.0f", km) : String(format: "%.1f", km)
}

/// 포인트 페이스 — 예측 하프 등가에서 Riegel 1.06(`mrProjectedRefMin`과 같은 지수)으로.
struct MRPointPaces: Equatable, Sendable {
    let fiveK: Double
    let tenK: Double
    let half: Double
    /// Daniels T 페이스 ≈ 1시간 대회 페이스. 일반 러너에게 1시간은 대략 10K와 하프 사이 — ⚠ 임의로 정함(중간값)
    var tempo: Double { (tenK + half) / 2 }
}

func mrPointPaces(halfEquivMin: Double) -> MRPointPaces? {
    guard halfEquivMin > 10 else { return nil }
    func pace(_ dM: Double) -> Double { halfEquivMin * pow(dM / MRDistance.dH, 1.06) * 60 / (dM / 1000) }
    return MRPointPaces(fiveK: pace(MRDistance.d5), tenK: pace(MRDistance.d10), half: pace(MRDistance.dH))
}

/// 계획 단계 → 포인트 종류. 회복·대회 주·따르는 주(○○ 계획)는 nil.
func mrPointKind(phase: String) -> MRPlanPoint.Kind? {
    switch phase {
    case "늘리기": return .speed
    case "유지": return .tempo
    case "대회 페이스": return .buildUp
    case "테이퍼": return .racePaceShort
    default: return nil
    }
}

/// 포인트 간격(일) — 최근 주당 러닝 4회 이상 7일 · 3회 14일 · 그 아래 nil(포인트 없음).
/// 엔진에 비공개 레벨이 없어 주당 횟수로 대신한다(설계 4절).
func mrPointIntervalDays(runsPerWeek: Double) -> Int? {
    let n = Int(runsPerWeek.rounded())
    if n >= 4 { return 7 }
    if n == 3 { return 14 }
    return nil
}

/// 계획 문구의 마지막 "이지(짧게/Easy/Short) Xkm × N회(x)"에서 숫자만 바꾼다. 언어·나머지 문구는 그대로. 못 찾으면 nil.
/// (`mrParsePlanBreakdown`과 같은 패턴)
func mrBreakdownReplacingEasy(_ text: String, easyKm: Double, runs: Int) -> String? {
    guard let re = try? NSRegularExpression(pattern: #"(?:이지|짧게|Easy|Short) ([0-9]+(?:\.[0-9]+)?)km × ([0-9]+)(?:회|x)"#) else { return nil }
    let ns = text as NSString
    guard let m = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).last else { return nil }
    // 뒤쪽(횟수)부터 바꿔야 앞쪽(거리) 범위가 밀리지 않는다
    let replacedRuns = ns.replacingCharacters(in: m.range(at: 2), with: "\(runs)") as NSString
    return replacedRuns.replacingCharacters(in: m.range(at: 1), with: mrPointKmString(easyKm))
}
