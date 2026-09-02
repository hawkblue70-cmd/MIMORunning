import Foundation

// ⚠ 회귀를 적합 범위 밖으로 외삽하지 말 것.
//   이 코드베이스에서 네 번 같은 실수가 있었다 —
//   더위 모델 심박 공변량, T3 세그먼트, 드리프트 pooled, HRPace 저심박.
//   데이터가 없는 구간의 값이 필요하면 회귀 대신
//   실측 구간의 중앙값을 쓰고, 그 표본 수를 화면에 밝힌다.
struct MRHRPaceModel {
    var ok = false
    var b0 = 0.0            // 절편 (30분 기준으로 흡수)
    var bSpeed = 0.0        // bpm per (m/min)
    var bTemp = 0.0
    var residSD = 0.0
    var r2 = 0.0            // 회귀 결정계수 (심박 예측 정확도)
    var n = 0
    var speedSpan = 0.0     // m/s
    var tier = "T0"
    var dataHRMin = 0.0     // 학습 데이터 심박 하한 — 이 아래는 외삽 구간
    var dataHRMax = 0.0     // 학습 데이터 심박 상한
    var dataSpeedMin = 0.0  // 학습 데이터 최저 속도 m/min (가장 느린 실측 페이스)

    /// 이 심박으로 달리면 페이스가 얼마인가 (초/km)
    ///
    /// ⚠ 목표 심박이 학습 데이터 심박 하한보다 낮으면 외삽이다.
    ///   선형 외삽은 데이터 범위를 벗어날수록 오차가 제곱으로 커지므로 nil을 돌려준다.
    func paceAtHR(_ hr: Double, tempC: Double = 15.0) -> Double? {
        guard ok, bSpeed > 0 else { return nil }
        // 목표 심박이 학습 데이터 하한보다 낮으면 외삽 → 계산 불가
        if dataHRMin > 0 && hr < dataHRMin { return nil }
        let adj = hr - b0 - bTemp * max(0, tempC - MR_REF_TEMP)
        let v = adj / bSpeed        // m/min
        guard v > 60 else {
            // ⚠ 여기 걸리면 절편이 목표 심박보다 높다는 뜻 —
            //   회귀가 잘못된 관계를 잡았다는 신호다. 조용히 넘기지 말 것.
            #if DEBUG
            print("[HRPace] paceAtHR(\(hr)) 실패: b0=\(b0) bSpeed=\(bSpeed) v=\(v)")
            #endif
            return nil
        }
        return 60_000.0 / v
    }
}

// MARK: - 실측 구간 중앙값 (이지 페이스 추정 본체)

/// 목표 심박 ±5bpm 구간 실측 런의 중앙값 결과.
///
/// 선형 회귀는 저심박 구간에 데이터가 적을 때 무너진다.
/// 실측 구간 중앙값은 데이터가 없으면 nil을 돌려줄 뿐, 잘못된 값을 만들지 않는다.
struct MRHRPaceLookup {
    let paceSec: Double   // 이지 페이스 중앙값 (sec/km)
    let n: Int            // 표본 수
    let hrLo: Double      // 구간 하한
    let hrHi: Double      // 구간 상한

    /// 근거줄 — 화면 표시용
    var basis: String {
        "심박 \(Int(hrLo.rounded()))~\(Int(hrHi.rounded()))bpm 구간 러닝 \(n)회의 중앙값"
    }
}

/// 목표 심박 ±5bpm 구간의 실측 페이스 중앙값.
///
/// ⚠ 회귀 대신 이 함수를 이지 페이스에 쓰는 이유:
///   저심박 구간에 데이터가 적으면 선형 회귀는 데이터 범위 바깥으로 선을 늘인다.
///   이 함수는 데이터가 있는 곳만 본다 — 부족하면 nil(계산 불가).
///   n < 5 이면 중앙값이 개인 하루치에 크게 흔들리므로 반환하지 않는다.
func mrEasyPaceFromRuns(
    runs: [MRWorkout],
    targetHR: Double,
    asOf: Date,
    halfBand: Double = 5.0,
    minN: Int = 5
) -> MRHRPaceLookup? {
    let cal = Calendar.current
    let lo = targetHR - halfBand
    let hi = targetHR + halfBand

    var paces: [Double] = []
    #if DEBUG
    struct _S { let date: Date; let hr: Double; let km: Double; let pac: Double }
    var dbgPassed: [_S] = []
    var rejRange = 0, rejIndoor = 0, rejNoData = 0, rejDur = 0, rejDist = 0, rejBand = 0, rejSpd = 0
    #endif

    for w in runs {
        let days = cal.dateComponents([.day], from: w.date,
                                      to: cal.startOfDay(for: asOf)).day ?? -1
        guard days >= 0, days <= 365 else {
            #if DEBUG
            rejRange += 1
            #endif
            continue
        }
        guard !w.indoor, let hr = w.hrAvg, let km = w.distanceKm else {
            #if DEBUG
            if w.indoor { rejIndoor += 1 } else { rejNoData += 1 }
            #endif
            continue
        }
        guard w.durationMin >= 20 else {
            #if DEBUG
            rejDur += 1
            #endif
            continue
        }
        guard km >= 2.0 else {
            #if DEBUG
            rejDist += 1
            #endif
            continue
        }
        guard hr >= lo && hr < hi else {
            #if DEBUG
            rejBand += 1
            #endif
            continue
        }
        let speed = km * 1000.0 / w.durationMin
        guard speed > 100, speed < 400 else {
            #if DEBUG
            rejSpd += 1
            #endif
            continue
        }
        let pac = 60_000.0 / speed
        paces.append(pac)
        #if DEBUG
        dbgPassed.append(_S(date: w.date, hr: hr, km: km, pac: pac))
        #endif
    }

    #if DEBUG
    print(String(format: "[HRPace:이지] 목표 %.1fbpm · 경계 %.1f~%.1fbpm · 통과 %d건",
                 targetHR, lo, hi, dbgPassed.count))
    let dfS = DateFormatter(); dfS.dateFormat = "yyyy-MM-dd"
    let sampleStr = dbgPassed.sorted { $0.date > $1.date }.prefix(8)
        .map { s in "\(dfS.string(from: s.date))(HR\(Int(s.hr)) · \(String(format: "%.1f", s.km))km · \(mrFormatPace(s.pac)))" }
        .joined(separator: " · ")
    if !sampleStr.isEmpty { print("[HRPace:이지] 표본 = \(sampleStr)") }
    var rej: [String] = []
    if rejRange  > 0 { rej.append("365일초과 \(rejRange)건") }
    if rejIndoor > 0 { rej.append("실내 \(rejIndoor)건") }
    if rejNoData > 0 { rej.append("데이터없음 \(rejNoData)건") }
    if rejDur    > 0 { rej.append("20분미만 \(rejDur)건") }
    if rejDist   > 0 { rej.append("2km미만 \(rejDist)건") }
    if rejBand   > 0 { rej.append("구간밖 \(rejBand)건") }
    if rejSpd    > 0 { rej.append("속도이상 \(rejSpd)건") }
    if !rej.isEmpty { print("[HRPace:이지] 제외 = \(rej.joined(separator: " · "))") }
    #endif

    guard paces.count >= minN else {
        #if DEBUG
        print(String(format: "[HRPace:이지] n=%d < %d → 계산 불가", paces.count, minN))
        #endif
        return nil
    }

    paces.sort()
    let mid = paces.count / 2
    let median = paces.count % 2 == 0
        ? (paces[mid - 1] + paces[mid]) / 2.0
        : paces[mid]

    #if DEBUG
    print("[HRPace:이지] 중앙값 \(mrFormatPace(median))")
    #endif

    return MRHRPaceLookup(paceSec: median, n: paces.count, hrLo: lo, hrHi: hi)
}

/// 워크아웃 단위 심박–속도 회귀.
///
///   HR ~ 1 + speed(m/min) + max(0, temp−15) + durationMin
///
/// duration 항은 심혈관 드리프트를 흡수한다. 절편에 30분치를 미리 더해
/// "30분짜리 러닝 기준"으로 해석하게 만든다.
///
/// ⚠ 여기는 심박이 **종속변수**다. 더위 모델과 반대 방향이므로 문제없다.
func mrFitHRPaceModel(runs: [MRWorkout], asOf: Date) -> MRHRPaceModel {
    var m = MRHRPaceModel()
    let cal = Calendar.current

    var X: [[Double]] = []
    var y: [Double] = []
    var speeds: [Double] = []
    #if DEBUG
    var allDates: [Date] = []
    var allTemps: [Double] = []
    #endif

    for w in runs {
        let days = cal.dateComponents([.day], from: w.date,
                                      to: cal.startOfDay(for: asOf)).day ?? -1
        guard days >= 0, days <= 365 else { continue }
        guard !w.indoor, let hr = w.hrAvg, let km = w.distanceKm else { continue }
        guard w.durationMin >= 20, km >= 2.0 else { continue }
        let speed = km * 1000.0 / w.durationMin
        guard speed > 100, speed < 400 else { continue }

        X.append([1.0, speed, max(0, (w.tempC ?? MR_REF_TEMP) - MR_REF_TEMP), w.durationMin])
        y.append(hr)
        speeds.append(speed)
        #if DEBUG
        allDates.append(w.date)
        allTemps.append(w.tempC ?? MR_REF_TEMP)
        #endif
    }
    guard X.count >= 8, let c = MRLinAlg.lstsq(X: X, y: y) else { return m }

    m.b0 = c[0] + c[3] * 30.0        // 30분 기준으로 흡수
    m.bSpeed = c[1]
    m.bTemp = c[2]
    m.residSD = MRLinAlg.residualSD(X: X, y: y, coef: c, ddof: min(4, X.count - 1))
    m.n = X.count
    m.speedSpan = (speeds.max()! - speeds.min()!) / 60.0
    m.dataHRMin = y.min() ?? 0
    m.dataHRMax = y.max() ?? 0
    m.dataSpeedMin = speeds.min() ?? 0

    // R² — 학습 데이터에서 심박을 얼마나 잘 설명하는가
    let yMean = y.reduce(0.0, +) / Double(y.count)
    let ssTot = y.reduce(0.0) { acc, yi in acc + (yi - yMean) * (yi - yMean) }
    let yHat  = X.map { row in row.indices.reduce(0.0) { $0 + c[$1] * row[$1] } }
    let ssRes = zip(y, yHat).reduce(0.0) { acc, pair in acc + (pair.0 - pair.1) * (pair.0 - pair.1) }
    m.r2 = ssTot > 0 ? 1.0 - ssRes / ssTot : 0.0

    m.ok = m.bSpeed > 0.005 && m.speedSpan >= 0.35
    m.tier = !m.ok ? "T1" : ((m.n >= 20 && m.speedSpan >= 0.6) ? "T2" : "T1")

    #if DEBUG
    // ── 기울기를 sec/km per bpm으로 (데이터 중심 HR에서 선형화) ──
    // dPace/dHR = -60000 × bSpeed / (HR - b0)²
    let midHR = (m.dataHRMin + m.dataHRMax) * 0.5
    let slopeSecPerBpm: Double = {
        let denom = (midHR - m.b0) * (midHR - m.b0)
        guard denom > 0 else { return 0 }
        return -60_000.0 * m.bSpeed / denom
    }()

    let sortedDates = allDates.sorted()
    let df = DateFormatter(); df.dateFormat = "yy.MM"
    let dateRangeStr = sortedDates.isEmpty ? "—"
        : "\(df.string(from: sortedDates.first!))~\(df.string(from: sortedDates.last!))"

    print(String(format: "[HRPace:회귀] n=%d (%@) · b0=%.1f bpm · 기울기=%.1f초/bpm(%.0fbpm기준) · R²=%.2f  [회귀모델·고정버킷·평균]",
                 m.n, dateRangeStr, m.b0, slopeSecPerBpm, midHR, m.r2))

    // ── 심박 구간별 실측 분포 ──
    let binDefs: [(lo: Double, hi: Double)] = [(0, 130), (130, 140), (140, 150), (150, 999)]
    for bin in binDefs {
        let pts = zip(y, speeds).filter { $0.0 >= bin.lo && $0.0 < bin.hi }
        guard !pts.isEmpty else { continue }
        let avgSpd = pts.map { $0.1 }.reduce(0.0, +) / Double(pts.count)
        let label: String = {
            if bin.lo == 0 { return String(format: "  ~%.0f  ", bin.hi) }
            if bin.hi >= 999 { return String(format: "%.0f~    ", bin.lo) }
            return String(format: "%.0f~%.0f", bin.lo, bin.hi)
        }()
        print(String(format: "[HRPace:회귀]   %@ : n=%-3d  평균 페이스 %@",
                     label, pts.count, mrFormatPace(60_000.0 / avgSpd)))
    }

    // ── 135bpm 예측 vs 130~140 실측 ──
    let pts130 = zip(y, speeds).filter { $0.0 >= 130 && $0.0 < 140 }
    if !pts130.isEmpty {
        let actualAvgSpd = pts130.map { $0.1 }.reduce(0.0, +) / Double(pts130.count)
        let predStr = m.paceAtHR(135.0).map { mrFormatPace($0) } ?? "범위밖/nil"
        print("[HRPace:회귀] 135bpm 예측 \(predStr) vs 130~140 실측 평균 \(mrFormatPace(60_000.0 / actualAvgSpd))")
    }

    // ── 저심박(<132) 런 상세 — 회귀를 당기는 아웃라이어 후보 ──
    let lowIdxs = y.indices.filter { y[$0] < 132 }
    if !lowIdxs.isEmpty {
        let dfDay = DateFormatter(); dfDay.dateFormat = "MM.dd"
        print("[HRPace:회귀] 저심박(<132) 런 \(lowIdxs.count)건:")
        for i in lowIdxs.sorted(by: { y[$0] < y[$1] }) {
            print(String(format: "[HRPace:회귀]   %@  HR=%.0f  페이스 %@",
                         dfDay.string(from: allDates[i]), y[i],
                         mrFormatPace(60_000.0 / speeds[i])))
        }
    }

    // ── 기온 보정 상태 ──
    if !allTemps.isEmpty {
        print(String(format: "[HRPace:회귀] bTemp=%.4f / 기온 %.0f~%.0f°C (더위 보정 %@)",
                     m.bTemp, allTemps.min()!, allTemps.max()!,
                     m.bTemp > 0.05 ? "작동" : "약함/역전"))
    }
    #endif

    return m
}

/// 심혈관 드리프트 — 같은 페이스에서 시간이 갈수록 심박이 오르는 정도.
///
/// 세션 **내부** 데이터로만 잴 수 있는 값이라 세그먼트가 필요하다.
/// (이건 세션 내 관계가 맞는 질문인 경우다 — 이지 페이스와 다르다)
///
/// ⚠ 예측식에는 넣지 않는다. Smyth & Muniz-Pumares 2022의 decoupling은
///   마라톤 레이스 전후반 비교이고, 훈련 주행의 드리프트가 같은 것이라는
///   근거가 없다. 화면에 **보여주기만** 한다.
/// 심혈관 드리프트 — 같은 페이스에서 시간이 갈수록 심박이 오르는 정도.
///
///   (HR − 세션평균) ~ (speed − 세션평균) + (elapsed − 세션평균)
///                     + 기온 × (elapsed − 세션평균)
///
/// ⚠ 두 가지를 고쳤다:
///
/// ① **세션 중심화(within-session centering)**
///    v1은 세션 구분 없이 pooled 회귀였다. 긴 세션이 더운 날에 몰려 있으면
///    "시간이 지나 심박이 올랐다"와 "그날이 더워 처음부터 높았다"가
///    구분되지 않는다.
///
/// ② **기온 상호작용**
///    드리프트는 고정 형질이 아니라 조건에 따라 변한다. 더위·탈수가
///    주된 기전이다(Coyle & González-Alonso 2001, Exerc Sport Sci Rev 29(2):88–92).
///    90일 창이면 여름만 담겨 "여름 값"을 그 사람 값으로 보고하게 된다.
///    → 창을 365일로 넓히고 기온을 넣어 15°C 기준으로 보고한다.
struct MRDriftModel {
    var ok = false
    var bpmPer10MinAtRef = 0.0      // 15°C 기준
    var bpmPer10MinPerDegC = 0.0    // 기온 1°C당 증가분
    var sessions = 0
    var tempSpanC = 0.0             // 기온 범위 — 좁으면 신뢰 못 함

    func bpmPer10Min(atC t: Double) -> Double {
        bpmPer10MinAtRef + bpmPer10MinPerDegC * (t - MR_REF_TEMP)
    }
}

func mrFitDrift(segments: [MRSegment],
                excludeIntervalStarts: Set<Date>) -> MRDriftModel {
    var m = MRDriftModel()
    let rows = segments.filter { !excludeIntervalStarts.contains($0.workoutStart) }
    let bySession = Dictionary(grouping: rows, by: \.workoutStart)
    guard rows.count >= 300, bySession.count >= 15 else { return m }

    var X: [[Double]] = [], y: [Double] = []
    for (_, segs) in bySession {
        guard segs.count >= 8 else { continue }
        let n = Double(segs.count)
        let mHR = segs.map(\.hr).reduce(0, +) / n
        let mSp = segs.map(\.speedMPerMin).reduce(0, +) / n
        let mEl = segs.map(\.elapsedMin).reduce(0, +) / n
        let t = segs.first?.tempC ?? MR_REF_TEMP
        for s in segs {
            let dEl = s.elapsedMin - mEl
            // 세션 중심화 → 절편 없음. [속도편차, 경과시간편차, 기온×경과시간편차]
            X.append([s.speedMPerMin - mSp, dEl, dEl * (t - MR_REF_TEMP)])
            y.append(s.hr - mHR)
        }
    }
    // ⚠ 세션 중심화를 했으므로 절편이 없다. lstsq에 절편 열 넣지 말 것.
    guard let c = MRLinAlg.lstsq(X: X, y: y) else { return m }

    m.bpmPer10MinAtRef    = c[1] * 10.0
    m.bpmPer10MinPerDegC  = c[2] * 10.0
    m.sessions = bySession.count
    let temps = bySession.values.compactMap { $0.first?.tempC }
    m.tempSpanC = (temps.max() ?? 0) - (temps.min() ?? 0)

    // ⚠ 기온 범위가 좁으면 기온 항을 분리할 수 없다 — 외삽보다 침묵.
    m.ok = m.bpmPer10MinAtRef > 0 && m.bpmPer10MinAtRef < 15 && m.tempSpanC >= 15
    return m
}

/// 세그먼트 단위 심박–속도 회귀 (T3).
///
///   HR ~ 1 + speed + max(0, temp−15) + elapsedMin
///
/// elapsedMin 항이 **심혈관 드리프트**를 흡수한다. 같은 페이스라도
/// 40분째 심박이 10분째보다 높은데, 그걸 통제하지 않으면
/// "느리게 뛸수록 심박이 높다"는 거꾸로 된 관계가 섞인다.
///
/// ⚠ **표본 크기를 그대로 믿으면 안 된다.**
///   한 세션에서 나온 40개 점은 서로 독립이 아니다(같은 날, 같은 몸, 같은 코스).
///   n=8,000으로 신뢰구간을 계산하면 **근거 없이 좁아진다.**
///   → 유효 표본을 **세션 수**로 잡고 잔차 SD를 그만큼 부풀린다.
///     (이게 1·2차 감사에서 반복해서 걸렸던 함정이다 —
///      LT1의 두 사전확률이 같은 HRmax를 공유하던 것과 같은 종류)
func mrFitHRPaceModelT3(segments: [MRSegment],
                        excludeIntervalStarts: Set<Date>) -> MRHRPaceModel {
    var m = MRHRPaceModel()

    // 인터벌 세션은 뺀다. 회복 구간의 (낮은 속도 + 높은 심박) 점이
    // 관계를 통째로 왜곡한다.
    let rows = segments.filter { !excludeIntervalStarts.contains($0.workoutStart) }
    let sessions = Set(rows.map(\.workoutStart))
    guard rows.count >= 200, sessions.count >= 8 else { return m }

    var X: [[Double]] = []
    var y: [Double] = []
    for s in rows {
        X.append([1.0, s.speedMPerMin,
                  max(0, (s.tempC ?? MR_REF_TEMP) - MR_REF_TEMP), s.elapsedMin])
        y.append(s.hr)
    }
    guard let c = MRLinAlg.lstsq(X: X, y: y) else { return m }

    m.b0 = c[0] + c[3] * 30.0            // 30분 시점 기준
    m.bSpeed = c[1]
    m.bTemp = c[2]

    let rawSD = MRLinAlg.residualSD(X: X, y: y, coef: c, ddof: 4)
    // 군집 보정: 유효 표본은 점 개수가 아니라 세션 수다
    let inflate = (Double(rows.count) / Double(sessions.count)).squareRoot()
    m.residSD = rawSD * inflate

    m.n = sessions.count                 // ★ 세션 수를 보고한다
    let sp = rows.map(\.speedMPerMin)
    m.speedSpan = (sp.max()! - sp.min()!) / 60.0
    m.ok = m.bSpeed > 0.005 && m.speedSpan >= 0.35
    m.tier = m.ok ? "T3" : "T1"
    return m
}
