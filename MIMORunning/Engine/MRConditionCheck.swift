import Foundation

// MARK: - 컨디션 점검 (디버그 로그 전용)
//
// "수면은 괜찮은데 컨디션이 별로" 원인을 지금 모으는 데이터로 가려 보기 위한 로그(2026-10-11).
// 최근 7일을 본인 평소(직전 28일)와 나란히 찍는다 — 판정·문장 없이 숫자만. 화면에는 아직 쓰지 않는다.
//   ① 부하  ② 기온  ③ 같은 속도·기온에서 심박(심박-페이스 모델 잔차)  ④ 안정시 심박
//   ⑤ HRV  ⑥ 호흡수·손목 온도  ⑦ 장거리 후반 진단
// 1분 회복(HRR1)은 HealthKitManager 쪽 지표라 성장 탭에서 따로 찍는다(`[컨디션 점검] 1분 회복`).

#if DEBUG
func mrConditionCheckLines(runs: [MRWorkout],
                           heatHR: MRHeatHRModel,
                           restingHR: [(date: Date, value: Double)],
                           hrvNights: [(date: Date, value: Double)],
                           respNights: [(date: Date, value: Double)],
                           tempNights: [(date: Date, value: Double)],
                           fatigue: [MRLongRunFatigue],
                           hardRunStarts: Set<Date>,
                           asOf: Date,
                           calendar cal: Calendar = .current) -> [String] {
    let today = cal.startOfDay(for: asOf)
    func daysAgo(_ d: Date) -> Int { cal.dateComponents([.day], from: cal.startOfDay(for: d), to: today).day ?? Int.min }
    func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
    func median(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted(), n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
    func f(_ v: Double?, _ digits: Int = 1) -> String { v.map { String(format: "%.\(digits)f", $0) } ?? "—" }
    func pace(_ s: Double?) -> String {
        guard let s, s > 0 else { return "—" }
        let t = Int(s.rounded()); return String(format: "%d'%02d\"", t / 60, t % 60)
    }
    let df = DateFormatter(); df.dateFormat = "M/d"
    let recent = runs.filter { (0...6).contains(daysAgo($0.date)) }
    let prior  = runs.filter { (7...34).contains(daysAgo($0.date)) }
    var out: [String] = []
    out.append("[컨디션 점검] 기준 \(df.string(from: today)) · 최근 7일(0~6일 전) vs 평소(7~34일 전, 4주)")

    // ① 부하
    let rKm = recent.compactMap(\.distanceKm).reduce(0, +)
    let rMin = recent.map(\.durationMin).reduce(0, +)
    let pKmWk = prior.compactMap(\.distanceKm).reduce(0, +) / 4
    let pMinWk = prior.map(\.durationMin).reduce(0, +) / 4
    let ac = mrDurationAcuteChronic(runs: runs, asOf: asOf, calendar: cal)
    let streak = mrConsecutiveRunDays(runs: runs, asOf: asOf, calendar: cal)
    let daily7: [Double] = (0...6).map { d in recent.filter { daysAgo($0.date) == d }.map(\.durationMin).reduce(0, +) }
    let hard7 = hardRunStarts.filter { (0...6).contains(daysAgo($0)) }.count
    let hard28 = hardRunStarts.filter { (7...34).contains(daysAgo($0)) }.count
    out.append(String(format: "[컨디션 점검] ① 부하 7일 %.1fkm · %.0f분 · %d회 | 평소 주 %.1fkm · %.0f분 | 분 기준 급성:만성 %@%@ · 연속 러닝 %d일 · 단조로움 %@ · 고강도 7일 %d회(평소 주 %.1f회)",
                      rKm, rMin, recent.count, pKmWk, pMinWk, f(ac.ratio, 2), ac.rising ? "(직전 7일보다 +15%↑)" : "",
                      streak, f(EffortLoad.monotony(daily: daily7), 2), hard7, Double(hard28) / 4))
    // 최근 가벼운 주(주 km가 앞 4주 평균의 80% 미만) — 회복 주 없이 이어진 기간
    let monday: (Date) -> Date = { EffortLoad.mondayStart(of: $0, calendar: cal) }
    let thisWeek = monday(asOf)
    var weekKm: [Date: Double] = [:]
    for w in runs { weekKm[monday(w.start), default: 0] += w.distanceKm ?? 0 }
    var lightAgo: Int? = nil
    for k in 1...52 {
        guard let wk = cal.date(byAdding: .day, value: -7 * k, to: thisWeek) else { break }
        let prev4 = (1...4).compactMap { cal.date(byAdding: .day, value: -7 * $0, to: wk) }.map { weekKm[$0] ?? 0 }
        let avg = prev4.reduce(0, +) / 4
        if avg > 0, (weekKm[wk] ?? 0) < avg * 0.8 { lightAgo = k; break }
    }
    let lastWeeks = (0...5).reversed().compactMap { k -> String? in
        guard let wk = cal.date(byAdding: .day, value: -7 * k, to: thisWeek) else { return nil }
        return "\(df.string(from: wk)) \(f(weekKm[wk] ?? 0))"
    }.joined(separator: " · ")
    out.append("[컨디션 점검]    주간 km(월요일 시작): \(lastWeeks) · 마지막 가벼운 주(앞 4주 평균의 80% 미만): \(lightAgo.map { "\($0)주 전" } ?? "52주 안에 없음")")

    // ② 기온
    let rTemp = recent.filter { !$0.indoor }.compactMap(\.tempC)
    let pTemp = prior.filter { !$0.indoor }.compactMap(\.tempC)
    let rHeat = recent.filter { !$0.indoor }.map { heatHR.delta($0.tempC) }
    let pHeat = prior.filter { !$0.indoor }.map { heatHR.delta($0.tempC) }
    out.append("[컨디션 점검] ② 기온 7일 평균 \(f(mean(rTemp)))°C(\(rTemp.count)회) vs 평소 \(f(mean(pTemp)))°C(\(pTemp.count)회) · 기온 탓 심박 +\(f(mean(rHeat)))bpm vs 평소 +\(f(mean(pHeat)))bpm (모델 \(heatHR.isFallback ? "기본값" : "개인"))")

    // ③ 같은 속도·기온 심박 — 평소(7일 전까지 1년) 러닝으로 맞춘 모델로 최근 러닝의 기대 심박을 내고 실제와 비교.
    //   모델 절편은 30분 기준이라 80분 넘는 러닝·인터벌은 평균에서 뺀다(줄에는 표시).
    let baseAsOf = cal.date(byAdding: .day, value: -7, to: today) ?? today
    let model = mrFitHRPaceModel(runs: runs, asOf: baseAsOf)
    func expectedHR(_ w: MRWorkout) -> Double? {
        guard model.ok, let km = w.distanceKm, km > 0, w.durationMin > 0 else { return nil }
        let speed = km * 1000 / w.durationMin
        return model.b0 + model.bSpeed * speed + model.bTemp * max(0, (w.tempC ?? MR_REF_TEMP) - MR_REF_TEMP)
    }
    func eligible(_ w: MRWorkout) -> Bool { !w.indoor && !w.isInterval && w.durationMin >= 20 && w.durationMin <= 80 }
    func residuals(_ ws: [MRWorkout]) -> [Double] {
        ws.filter(eligible).compactMap { w in w.hrAvg.flatMap { hr in expectedHR(w).map { hr - $0 } } }
    }
    out.append("[컨디션 점검] ③ 같은 속도·기온 심박(실제−기대) 7일 \(f(mean(residuals(recent))))bpm(\(residuals(recent).count)회) vs 평소 \(f(mean(residuals(prior))))bpm(\(residuals(prior).count)회) · 모델 n=\(model.n) R²=\(f(model.r2, 2)) 잔차SD \(f(model.residSD))bpm\(model.ok ? "" : " · 모델 불가")")
    let last14 = runs.filter { (0...13).contains(daysAgo($0.date)) }.sorted { $0.start < $1.start }
    for w in last14 {
        let exp = expectedHR(w)
        let res = w.hrAvg.flatMap { hr in exp.map { hr - $0 } }
        let tag = w.isInterval ? " 인터벌" : (w.durationMin > 80 ? " 80분+" : "")
        out.append("[컨디션 점검]    \(df.string(from: w.date)) \(f(w.distanceKm))km \(pace(w.paceSecPerKm)) \(Int(w.durationMin.rounded()))분 · 심박 \(f(w.hrAvg, 0)) · 기대 \(f(exp, 0)) · 차이 \(res.map { String(format: "%+.0f", $0) } ?? "—") · \(f(w.tempC, 0))°C\(tag)")
    }

    // ④ 안정시 심박
    let rRHR = restingHR.filter { (0...6).contains(daysAgo($0.date)) }.map(\.value)
    let pRHR = restingHR.filter { (7...34).contains(daysAgo($0.date)) }.map(\.value)
    let rhrDays = restingHR.filter { (0...6).contains(daysAgo($0.date)) }
        .map { "\(df.string(from: $0.date)) \(Int($0.value.rounded()))" }.joined(separator: " · ")
    out.append("[컨디션 점검] ④ 안정시 심박 7일 평균 \(f(mean(rRHR))) vs 평소 중앙값 \(f(median(pRHR))) · \(rhrDays.isEmpty ? "자료 없음" : rhrDays)")

    // ⑤ HRV
    let rHRV = hrvNights.filter { (0...6).contains(daysAgo($0.date)) }.map(\.value)
    let pHRV = hrvNights.filter { (7...34).contains(daysAgo($0.date)) }.map(\.value)
    out.append("[컨디션 점검] ⑤ HRV 7일 평균 \(f(mean(rHRV)))ms(\(rHRV.count)밤) vs 평소 중앙값 \(f(median(pHRV)))ms(\(pHRV.count)밤)")

    // ⑥ 호흡수·손목 온도 — 손목 온도는 이미 기준선 대비 편차값
    let rResp = respNights.filter { (0...6).contains(daysAgo($0.date)) }.map(\.value)
    let pResp = respNights.filter { (7...34).contains(daysAgo($0.date)) }.map(\.value)
    let rTempN = tempNights.filter { (0...6).contains(daysAgo($0.date)) }.map(\.value)
    let pTempN = tempNights.filter { (7...34).contains(daysAgo($0.date)) }.map(\.value)
    out.append("[컨디션 점검] ⑥ 호흡수 7일 \(f(mean(rResp)))회/분 vs 평소 \(f(median(pResp))) · 손목 온도 7일 \(f(mean(rTempN), 2)) vs 평소 \(f(median(pTempN), 2))°C")

    // ⑦ 장거리 후반 진단(8주)
    let v = MRLateRunPattern.aggregate(fatigue: fatigue, asOf: asOf)
    let lates = fatigue.filter { (0...55).contains(daysAgo($0.date)) }.sorted { $0.start < $1.start }
        .map { "\(df.string(from: $0.date)) \(f($0.distanceKm))km \($0.lateKind?.rawValue ?? "진단 불가")" }.joined(separator: " · ")
    out.append("[컨디션 점검] ⑦ 장거리 후반 8주 \(v.evaluated)회 평가 · 우세 \(v.dominant?.rawValue ?? "없음")(\(v.dominantCount)) · \(lates.isEmpty ? "롱런 요약 없음(성장 탭을 열면 채워짐)" : lates)")
    return out
}
#endif
