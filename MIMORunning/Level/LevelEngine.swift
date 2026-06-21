import Foundation

// MARK: - Level Bucket

enum LevelBucket: Int, Comparable, CaseIterable {
    case beginner    = 0  // 초보
    case novice      = 1  // 하수
    case intermediate = 2 // 중수
    case advanced    = 3  // 고수
    case elite       = 4  // 신

    static func < (lhs: LevelBucket, rhs: LevelBucket) -> Bool { lhs.rawValue < rhs.rawValue }

    var koreanName: String {
        switch self {
        case .beginner:     "초보"
        case .novice:       "하수"
        case .intermediate: "중수"
        case .advanced:     "고수"
        case .elite:        "신"
        }
    }
}

// MARK: - User Level

struct UserLevel {
    let bucket: LevelBucket
    let ageGrade: Double?        // WMA age-grade percentage (0–100+)
    let best5KEquivSec: Double?  // Riegel-converted 5K equivalent (seconds)
    let best5KDate: Date?        // date of the activity that produced best5KEquivSec
    let vdot: Double?            // Daniels-Gilbert VDOT estimate
}

// MARK: - Level Engine

struct LevelEngine {

    private static let bestBucketKey = "bestLevelBucketRaw"

    // MARK: - Main entry

    /// Pure computation — no HealthKit access. Pass characteristics from HealthKitManager.
    static func compute(
        activities: [Activity],
        dateOfBirth: DateComponents?,
        isMale: Bool?
    ) -> UserLevel {
        let runs = activities.filter { $0.type == .running }

        // Cold start: fewer than 3 runs → 초보
        guard runs.count >= 3 else {
            return persist(.beginner, ageGrade: nil, t5K: nil, t5KDate: nil, vdot: nil)
        }

        // 초보 gate: must have at least one continuous run ≥ 5 km
        guard runs.contains(where: { $0.distance >= 5000 }) else {
            return persist(.beginner, ageGrade: nil, t5K: nil, t5KDate: nil, vdot: nil)
        }

        // Best 5K equivalent (Riegel) from last 12 months — matches the activity
        // fetch window so no extra data is loaded.
        let cutoff = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? .distantPast
        let windowRuns = runs.filter { $0.date >= cutoff && $0.distance >= 2000 && $0.distance <= 50000 }
        let bestEntry = windowRuns
            .compactMap { run -> (equiv: Double, date: Date)? in
                guard let e = riegelFiveKEquiv(run: run) else { return nil }
                return (e, run.date)
            }
            .min(by: { $0.equiv < $1.equiv })

        guard let t5K = bestEntry?.equiv else {
            return persist(.beginner, ageGrade: nil, t5K: nil, t5KDate: nil, vdot: nil)
        }
        let t5KDate = bestEntry?.date

        let male = isMale ?? true

        // Axis 1: percentile bucket from 5K time
        let pctBucket = percentileBucket(t5KSec: t5K, isMale: male)

        // Axis 2: age-grade bucket (only when birthdate is available)
        var ageGrade: Double? = nil
        var agBucket: LevelBucket = pctBucket

        if let dob = dateOfBirth, let birthYear = dob.year, birthYear > 1900 {
            let age = Calendar.current.component(.year, from: Date()) - birthYear
            let factor = ageFactor5K(age: age, isMale: male)
            // Road 5K open world records: men 12:49 (769s), women 14:19 (859s)
            let wr = male ? 769.0 : 859.0
            // Age-adjusted standard = WR / factor (lenient for older athletes)
            let standard = wr / factor
            let ag = standard / t5K * 100
            ageGrade = ag
            agBucket = ageBucket(ag)
        }

        // 2-axis cross-validation: if they disagree, take the more lenient (higher) bucket
        let rawBucket = ageGrade != nil ? max(pctBucket, agBucket) : pctBucket

        // VDOT (Daniels-Gilbert, publicly documented formula)
        let vdot = danielsVDOT(fiveKSec: t5K)

        return persist(rawBucket, ageGrade: ageGrade, t5K: t5K, t5KDate: t5KDate, vdot: vdot)
    }

    // MARK: - No-demotion persistence (UserDefaults)

    @discardableResult
    private static func persist(
        _ bucket: LevelBucket,
        ageGrade: Double?,
        t5K: Double?,
        t5KDate: Date?,
        vdot: Double?
    ) -> UserLevel {
        let storedRaw = UserDefaults.standard.integer(forKey: bestBucketKey)
        let storedBucket = LevelBucket(rawValue: storedRaw) ?? .beginner
        let finalBucket = max(bucket, storedBucket)  // never demote
        if finalBucket.rawValue > storedRaw {
            UserDefaults.standard.set(finalBucket.rawValue, forKey: bestBucketKey)
        }
        return UserLevel(bucket: finalBucket, ageGrade: ageGrade, best5KEquivSec: t5K, best5KDate: t5KDate, vdot: vdot)
    }

    // MARK: - Riegel formula
    // t5K = t_actual × (5000 / d_actual)^1.06
    // Converts any distance run to a 5K time equivalent.

    static func riegelFiveKEquiv(run: Activity) -> Double? {
        guard run.distance > 0, run.duration > 0 else { return nil }
        return run.duration * pow(5000.0 / run.distance, 1.06)
    }

    // MARK: - Percentile thresholds
    // Based on parkrun global completion statistics and race database distributions.
    // Men  → 신 <18:00 / 고수 <22:00 / 중수 <28:00 / 하수 <35:00 / 초보 ≥35:00
    // Women→ 신 <21:00 / 고수 <26:00 / 중수 <34:00 / 하수 <42:00 / 초보 ≥42:00

    static func percentileBucket(t5KSec: Double, isMale: Bool) -> LevelBucket {
        let (elite, advanced, intermediate, novice): (Double, Double, Double, Double) = isMale
            ? (1080, 1320, 1680, 2100)
            : (1260, 1560, 2040, 2520)
        if t5KSec < elite        { return .elite }
        if t5KSec < advanced     { return .advanced }
        if t5KSec < intermediate { return .intermediate }
        if t5KSec < novice       { return .novice }
        return .beginner
    }

    // MARK: - Age-grade buckets (CLAUDE.md 4.3)
    // 하수 <55% / 중수 55–65% / 고수 65–80% / 신 80%+

    static func ageBucket(_ ag: Double) -> LevelBucket {
        if ag >= 80 { return .elite }
        if ag >= 65 { return .advanced }
        if ag >= 55 { return .intermediate }
        if ag >= 40 { return .novice }
        return .beginner
    }

    // MARK: - WMA age factors (polynomial approximation, 5000m)
    // Open polynomial approximation of the WMA age-grading methodology.
    // Coefficients derived from publicly documented age-decline curves for distance running.
    // Men and women have separate decline rates reflecting physiological differences.
    // Reference: Jones (2007), WMA methodology papers, open running literature.

    static func ageFactor5K(age: Int, isMale: Bool) -> Double {
        let a = Double(max(15, age))
        if isMale {
            guard a > 35 else { return 1.0 }
            let x = a - 35
            // Men decline ~0.37%/year at 35, accelerating slightly with age
            return max(0.25, 1.0 - 0.003690 * x - 0.0001210 * x * x)
        } else {
            guard a > 35 else { return 1.0 }
            let x = a - 35
            // Women decline ~0.42%/year at 35
            return max(0.25, 1.0 - 0.004220 * x - 0.0001160 * x * x)
        }
    }

    // MARK: - Daniels-Gilbert VDOT (publicly documented formula)
    // From Jack Daniels "Daniels' Running Formula"; formula widely published
    // in running science literature and open-source projects.
    // v = speed in m/min, t = time in minutes

    static func danielsVDOT(fiveKSec: Double) -> Double {
        let t = fiveKSec / 60.0
        let v = 5000.0 / fiveKSec * 60.0           // m/min
        let vo2 = v * (0.000104 * v + 0.182258) - 4.6
        let pct  = 0.8
                 + 0.1894393 * exp(-0.012778  * t)
                 + 0.2989558 * exp(-0.1932605 * t)
        guard pct > 0 else { return 0 }
        return vo2 / pct
    }

    // MARK: - Formatted helpers (for debug display)

    static func formattedTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
