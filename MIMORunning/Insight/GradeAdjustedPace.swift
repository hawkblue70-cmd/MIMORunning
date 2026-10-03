import Foundation

/// GAP — 경사 조정 페이스(Grade Adjusted Pace).
///
/// 언덕에서 같은 노력을 써도 페이스는 느려진다. 그 느려짐을 걷어내 "평지였다면 몇 분 페이스였나"로
/// 환산한다. 코스가 다른 러닝을 같은 잣대로 비교할 수 있게 하는 것이 목적이다.
///
/// 근거: Minetti et al. (2002) "Energy cost of walking and running at extreme uphill and downhill
/// slopes" — 경사별 러닝 에너지 비용 C(i) [J/kg/m]를 5차 다항식으로 제시한 공개 논문.
/// 독점 표를 옮기지 않고 공식만 구현한다(CLAUDE.md 4.2).
enum GradeAdjustedPace {

    /// 평지 러닝의 에너지 비용 [J/kg/m]
    static let flatCost: Double = 3.6

    /// 공식의 유효 범위를 넘는 경사는 잘라낸다. ±20%면 계단에 가까운 경사로, 실제 러닝의 상한이다.
    static let maxGrade: Double = 0.20

    /// 내리막 이득을 얼마나 인정할지. 대사 비용 모델은 내리막을 과대평가한다 —
    /// 급한 내리막은 제동·편심 수축 부담 때문에 에너지가 적게 든다고 그만큼 빨라지지 않는다.
    /// 그래서 내리막에서 생기는 보정만 절반으로 줄인다.
    static let downhillDamping: Double = 0.5

    /// Minetti 경사별 에너지 비용 C(i) [J/kg/m]. i = 상승/수평거리 (0.05 = 5% 오르막)
    static func energyCost(grade: Double) -> Double {
        let i = min(max(grade, -maxGrade), maxGrade)
        let i2 = i * i, i3 = i2 * i, i4 = i3 * i, i5 = i4 * i
        return 155.4 * i5 - 30.4 * i4 - 43.3 * i3 + 46.3 * i2 + 19.5 * i + 3.6
    }

    /// 실제 페이스에 곱하면 평지 등가 페이스가 되는 계수.
    /// 오르막은 1보다 작고(= GAP이 더 빠름), 내리막은 1보다 크다(= GAP이 더 느림).
    static func factor(grade: Double) -> Double {
        let cost = energyCost(grade: grade)
        guard cost > 0.1 else { return 1 }
        let raw = flatCost / cost
        // 내리막(raw > 1)만 감쇠
        return raw > 1 ? 1 + (raw - 1) * downhillDamping : raw
    }

    // MARK: - 활동 단위 계산

    /// 스플릿과 고도 프로파일로 러닝 전체의 GAP(초/km)을 구한다.
    /// 고도는 GPS 노이즈가 커서 평활화 후 100m 간격으로 리샘플해 구간 경사를 낸다.
    /// 스플릿 하나 안에서도 오르내림이 섞이므로, 구간 계수를 거리로 가중 평균해 스플릿에 적용한다.
    static func compute(splits: [SplitData],
                        altitudeProfile: [(distanceKm: Double, altitude: Double)]) -> Double? {
        guard !splits.isEmpty else { return nil }
        let segments = gradeSegments(from: altitudeProfile)
        guard !segments.isEmpty else { return nil }

        var equivalentTime = 0.0
        var totalDistance = 0.0
        var cursor = 0.0                     // 이 스플릿이 시작하는 누적 거리(m)

        for split in splits.sorted(by: { $0.id < $1.id }) {
            let start = cursor
            let end = cursor + split.distanceM
            cursor = end
            guard split.distanceM > 0, split.paceSecPerKm > 0 else { continue }

            let f = averageFactor(from: segments, start: start, end: end)
            equivalentTime += (split.distanceM / 1000) * split.paceSecPerKm * f
            totalDistance += split.distanceM
        }
        guard totalDistance > 0 else { return nil }
        return equivalentTime / (totalDistance / 1000)
    }

    /// 경로 표본(누적 거리·고도·경과 시간)에서 **전체 보정 계수**를 구한다.
    /// 스플릿이 없는 과거 러닝(백필)용 — 반환값을 실제 평균 페이스에 곱하면 GAP이 된다.
    ///
    /// 페이스를 GPS 거리로 다시 계산하지 않고 계수만 뽑는 이유: GPS 누적 거리는 HealthKit이
    /// 기록한 거리와 조금씩 다르다. 계수만 쓰면 실제 페이스와 같은 기준을 유지할 수 있다.
    static func overallFactor(
        routeSamples: [(distanceM: Double, altitude: Double, time: TimeInterval)]
    ) -> Double? {
        guard routeSamples.count >= 3 else { return nil }
        let profile = routeSamples.map { (distanceKm: $0.distanceM / 1000, altitude: $0.altitude) }
        let smoothed = smoothAltitudes(profile)
        let stepM = 100.0
        let totalM = routeSamples.last?.distanceM ?? 0
        guard totalM >= stepM else { return nil }
        guard hasRealElevation(profile) else { return 1 }   // 평지(노이즈뿐)면 보정 없음 — 편향 방지

        var weighted = 0.0      // Σ(소요시간 × 계수)
        var totalTime = 0.0
        var d = 0.0
        while d < totalM {
            let end = min(d + stepM, totalM)
            guard end - d > 1 else { break }
            let t0 = time(at: d, in: routeSamples)
            let t1 = time(at: end, in: routeSamples)
            let dt = t1 - t0
            defer { d = end }
            guard dt > 0, dt.isFinite else { continue }
            let a0 = altitude(at: d, in: smoothed)
            let a1 = altitude(at: end, in: smoothed)
            let f = factor(grade: (a1 - a0) / (end - d))
            weighted += dt * f
            totalTime += dt
        }
        guard totalTime > 0 else { return nil }
        return weighted / totalTime
    }

    /// 누적 거리(m) 지점의 경과 시간 — 표본 사이는 선형 보간
    private static func time(at meters: Double,
                             in samples: [(distanceM: Double, altitude: Double, time: TimeInterval)])
        -> TimeInterval {
        guard let first = samples.first, let last = samples.last else { return 0 }
        if meters <= first.distanceM { return first.time }
        if meters >= last.distanceM { return last.time }
        for i in 1..<samples.count {
            let s0 = samples[i - 1], s1 = samples[i]
            guard meters <= s1.distanceM else { continue }
            let span = s1.distanceM - s0.distanceM
            guard span > 0 else { return s1.time }
            let t = (meters - s0.distanceM) / span
            return s0.time + (s1.time - s0.time) * t
        }
        return last.time
    }

    /// KPI 페이스 셀 아래 보조 표기 — "평지 환산 6'11"".
    /// ⚠ 리듬·폼·퍼포먼스 카드가 **이 함수 하나만** 쓴다. 카드마다 따로 만들면 기준이 갈라진다.
    /// 실제 페이스와 5초 미만 차이면 nil — 평지에서 띄우면 노이즈일 뿐이다.
    static func kpiText(splits: [SplitData],
                        altitudeProfile: [(distanceKm: Double, altitude: Double)],
                        actualPaceSecPerKm: Double?) -> String? {
        guard !splits.isEmpty, !altitudeProfile.isEmpty,
              hasRealElevation(altitudeProfile),
              let actual = actualPaceSecPerKm,
              let gap = compute(splits: splits, altitudeProfile: altitudeProfile),
              abs(gap - actual) >= 5
        else { return nil }
        let secs = Int(gap.rounded())
        let paceText = "\(secs / 60)'\(String(format: "%02d", secs % 60))\""
        // 영문은 러너에게 통용되는 GAP 그대로, 한국어는 뜻이 바로 읽히는 "평지 환산"
        return AppLanguage.shared.s("평지 환산 \(paceText)", "GAP \(paceText)", ja: "平地換算 \(paceText)")
    }

    /// 지속 경사로 볼 최소 고도 변화(m) — 1km 안에서 한 방향으로 이만큼 변해야 한다(평균 1% 경사).
    static let sustainedChangeM: Double = 10
    static let sustainedWindowM: Double = 1000

    /// 경사 보정을 할 만큼 실제 오르내림이 있는가 — **어느 1km 구간에서든 고도가 10m 이상 한 방향으로 변했는가.**
    /// ⚠ 평지 트랙에서도 GPS 고도는 바퀴마다 몇 m씩 오르내린다. 내리막 이득만 절반으로 줄이는
    ///   비대칭(downhillDamping) 때문에 이 노이즈가 상쇄되지 않고 "더 빨랐을 것"으로 쌓인다
    ///   (7'06" 트랙 러닝이 평지 환산 7'02"로 뜬 사례). 그래서 기준 미달이면 계수를 1로 둔다 —
    ///   표기뿐 아니라 폼 기준선·단계 보정·백필까지 같은 판단을 쓴다.
    /// 누적 상승 ÷ 전체 거리로 재지 않는 이유: 오르막이 코스 일부에 몰리면 평지 구간에 희석돼
    ///   분명한 언덕(5km 2% 오르막 + 5km 평지)도 평지로 읽힌다. 노이즈는 짧은 주기로 오르내려
    ///   1km 안에서 상쇄되고, 실제 언덕은 한 방향으로 쌓인다. 내리막만 있는 코스도 잡힌다.
    static func hasRealElevation(_ profile: [(distanceKm: Double, altitude: Double)]) -> Bool {
        guard profile.count >= 3 else { return false }
        let smoothed = smoothAltitudes(profile)
        let totalM = (smoothed.last?.distanceKm ?? 0) * 1000
        guard totalM > 0 else { return false }
        let stepM = 100.0
        let window = min(sustainedWindowM, totalM)
        var d = 0.0
        while d + window <= totalM + 1e-6 {
            let change = abs(altitude(at: min(d + window, totalM), in: smoothed) - altitude(at: d, in: smoothed))
            if change >= sustainedChangeM { return true }
            d += stepM
        }
        return false
    }

    /// 전반·후반 순 고도 변화가 이만큼(m) 다르면 두 반을 같은 조건으로 비교하지 않는다 — 심박 캡션·폼 전후반 비교가 같이 쓴다.
    static let halvesClimbGapM: Double = 15

    /// 전반·후반 순 고도 변화(m). x는 거리(km) 또는 시간(초) — 반은 x의 가운데로 나눈다. 5점 이동평균으로 GPS 고도 잡음을 누른다.
    /// 지속 경사(`hasRealElevation`와 같은 1km·10m 기준)가 없는 코스면 nil — 평지 트랙의 고도 흔들림으로 판단하지 않는다.
    static func halvesNetClimb(_ pts: [(x: Double, altitude: Double)]) -> (first: Double, second: Double)? {
        guard pts.count >= 6, let x0 = pts.first?.x, let x1 = pts.last?.x, x1 > x0 else { return nil }
        let w = 5
        let sm: [(x: Double, altitude: Double)] = pts.indices.map { i in
            let lo = max(0, i - w / 2), hi = min(pts.count - 1, i + w / 2)
            let a = pts[lo...hi].map(\.altitude).reduce(0, +) / Double(hi - lo + 1)
            return (pts[i].x, a)
        }
        // 지속 경사 게이트 — 순 변화가 한쪽이라도 10m 이상이어야 언덕 코스로 본다
        let mid = (x0 + x1) / 2
        func alt(at x: Double) -> Double {
            guard let j = sm.firstIndex(where: { $0.x >= x }) else { return sm.last!.altitude }
            guard j > 0 else { return sm[0].altitude }
            let a = sm[j - 1], b = sm[j]
            let t = b.x > a.x ? (x - a.x) / (b.x - a.x) : 0
            return a.altitude + t * (b.altitude - a.altitude)
        }
        let first = alt(at: mid) - alt(at: x0)
        let second = alt(at: x1) - alt(at: mid)
        guard max(abs(first), abs(second)) >= sustainedChangeM else { return nil }
        return (first, second)
    }

    // MARK: - Internals

    /// 100m 구간별 (시작거리m, 끝거리m, 보정계수)
    static func gradeSegments(from profile: [(distanceKm: Double, altitude: Double)])
        -> [(start: Double, end: Double, factor: Double)] {
        guard profile.count >= 3 else { return [] }
        let smoothed = smoothAltitudes(profile)
        let stepM = 100.0
        let totalM = (smoothed.last?.distanceKm ?? 0) * 1000
        guard totalM >= stepM else { return [] }

        let isHilly = hasRealElevation(profile)   // 평지(노이즈뿐)면 계수 1 — 편향 방지
        var result: [(start: Double, end: Double, factor: Double)] = []
        var d = 0.0
        while d < totalM {
            let end = min(d + stepM, totalM)
            guard end - d > 1 else { break }
            let a0 = altitude(at: d, in: smoothed)
            let a1 = altitude(at: end, in: smoothed)
            let grade = (a1 - a0) / (end - d)
            result.append((start: d, end: end, factor: isHilly ? factor(grade: grade) : 1))
            d = end
        }
        return result
    }

    /// GPS 고도 노이즈 제거 — 5점 이동 평균. 이걸 빼면 평지에서도 경사가 ±3%씩 튄다.
    private static func smoothAltitudes(_ profile: [(distanceKm: Double, altitude: Double)])
        -> [(distanceKm: Double, altitude: Double)] {
        let window = 5
        guard profile.count > window else { return profile }
        let half = window / 2
        return profile.enumerated().map { i, point in
            let lo = max(0, i - half), hi = min(profile.count - 1, i + half)
            let slice = profile[lo...hi]
            let avg = slice.reduce(0.0) { $0 + $1.altitude } / Double(slice.count)
            return (distanceKm: point.distanceKm, altitude: avg)
        }
    }

    /// 누적 거리(m) 지점의 고도 — 프로파일 점 사이는 선형 보간
    private static func altitude(at meters: Double,
                                 in profile: [(distanceKm: Double, altitude: Double)]) -> Double {
        let km = meters / 1000
        guard let first = profile.first, let last = profile.last else { return 0 }
        if km <= first.distanceKm { return first.altitude }
        if km >= last.distanceKm { return last.altitude }
        for i in 1..<profile.count {
            let p0 = profile[i - 1], p1 = profile[i]
            guard km <= p1.distanceKm else { continue }
            let span = p1.distanceKm - p0.distanceKm
            guard span > 0 else { return p1.altitude }
            let t = (km - p0.distanceKm) / span
            return p0.altitude + (p1.altitude - p0.altitude) * t
        }
        return last.altitude
    }

    /// [start, end) 구간에 걸친 보정 계수의 거리 가중 평균
    private static func averageFactor(from segments: [(start: Double, end: Double, factor: Double)],
                                      start: Double, end: Double) -> Double {
        var weighted = 0.0
        var covered = 0.0
        for seg in segments {
            let lo = max(seg.start, start)
            let hi = min(seg.end, end)
            guard hi > lo else { continue }
            weighted += seg.factor * (hi - lo)
            covered += hi - lo
        }
        guard covered > 0 else { return 1 }
        return weighted / covered
    }
}
