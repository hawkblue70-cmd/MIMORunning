import Foundation

// MARK: - 워크아웃 한 건
//
// HealthKit에서 읽어온 러닝 한 건. 계산 엔진은 이 타입만 본다.
// (HealthKit 의존성을 여기서 끊어야 테스트에 가짜 데이터를 넣을 수 있다)
struct MRWorkout: Codable {
    let start: Date
    let durationMin: Double
    let distanceKm: Double?
    let hrAvg: Double?
    let hrMax: Double?
    let tempC: Double?          // HKWeatherTemperature
    let humidity: Double?       // 0~100
    let indoor: Bool

    /// 구조화된 인터벌 세션인가.
    ///
    /// ⚠ 이 값이 필요한 이유는 두 가지다:
    ///   ① 인터벌은 평균 심박이 높아 대회급 노력 게이트를 통과한다.
    ///      하지만 인터벌의 **평균 페이스는 대회 페이스가 아니다**
    ///      (질주 구간 + 회복 구간의 평균이다).
    ///      지수 회귀에 넣으면 개인 지수가 오염된다.
    ///   ② 의도한 고강도를 "이지를 너무 빠르게 뛴 것"으로 세면 안 된다.
    ///      인터벌 1회 + 이지 3회는 건강한 구성이지 문제가 아니다.
    let isInterval: Bool

    var date: Date {
        Calendar.current.startOfDay(for: start)
    }

    /// 초/km
    var paceSecPerKm: Double? {
        guard let d = distanceKm, d > 0 else { return nil }
        return durationMin * 60.0 / d
    }

    /// m/min
    var speedMPerMin: Double? {
        guard let d = distanceKm, durationMin > 0 else { return nil }
        return d * 1000.0 / durationMin
    }
}

// MARK: - 확신도
//
// 모든 추정치는 "얼마나 믿을 만한가"를 같이 들고 다닌다.
// 불확실할 때 불확실하다고 말하는 것이 이 앱의 원칙이다.
enum MRConfidence: Int, Comparable {
    case none = 0, low, medium, high

    var label: String {
        switch self {
        case .none:   return "없음"
        case .low:    return "낮음"
        case .medium: return "보통"
        case .high:   return "높음"
        }
    }

    static func < (a: MRConfidence, b: MRConfidence) -> Bool {
        a.rawValue < b.rawValue
    }
}

// MARK: - 근거를 달고 다니는 추정치
//
// basis는 UI에 그대로 노출한다. 사용자가 탭하면 왜 이 숫자인지 볼 수 있어야 한다.
struct MRInference {
    let value: Double
    let confidence: MRConfidence
    let basis: [String]
}

// MARK: - 대회급 노력
//
// 실제 대회이거나, 대회에 준하는 강도로 달린 기록.
// 지수 적합과 예측의 재료가 된다.
struct MRRaceEffort {
    let date: Date
    let distanceM: Double
    let timeMin: Double
    var timeMinRef: Double      // 기온 15°C 기준으로 환산한 값
    let tempC: Double?
    let label: String           // "10K" / "하프" / "풀" / "12.4K"
    let isConfirmedRace: Bool   // 대회 매칭으로 확정된 건인지

    var vdot: Double {
        MIMORunning.vdot(distanceM: distanceM, timeMin: timeMin)
    }
}

// MARK: - 예측 결과
struct MRPrediction {
    let label: String
    let distanceM: Double
    let midMin: Double
    let loMin: Double
    let hiMin: Double
    let confidence: MRConfidence
    let basis: [String]
}

// MARK: - 시간 포맷
func mrFormatHMS(_ minutes: Double) -> String {
    let total = Int((minutes * 60).rounded())
    return String(format: "%d:%02d:%02d",
                  total / 3600, (total % 3600) / 60, total % 60)
}

/// 사람에게 보여줄 때 쓰는 포맷. 한 시간 미만이면 시(時)를 떼어낸다.
/// (`mrFormatHMS`는 계산·검증용이라 그대로 둔다)
func mrFormatDisplay(_ minutes: Double) -> String {
    let total = Int((minutes * 60).rounded())
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                 : String(format: "%d분 %02d초", m, s)
}

func mrFormatPace(_ secPerKm: Double) -> String {
    // ⚠ 버림(Int, 반올림 아님) + '/" 기호 — Activity.formattedPace와 동일.
    //   반올림이 다르면 같은 러닝이 목록에서 6'28"인데 카드에서 6:29로 보인다.
    let s = Int(secPerKm)
    return String(format: "%d'%02d\"", s / 60, s % 60)
}
