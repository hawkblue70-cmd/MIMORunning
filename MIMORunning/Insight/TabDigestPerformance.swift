import Foundation

/// 퍼포먼스 카드 판정(디커플링·7일 부하 라벨/문장·복귀·이지 비율 알림) + 오늘의 인사이트 퍼포먼스 블록 신호.
/// 카드(`PerformanceInsightCard`)와 요약이 같은 함수를 불러 같은 문장을 쓴다 — 카드는 `shade`를 원래 색으로 바꿔 쓴다.
/// 설계: docs/superpowers/specs/2026-10-14-today-insight-tab-digest-design.md §4.3·§5
enum TabDigestPerformance {

    // MARK: - 유산소 디커플링 (옮김: PerformanceInsightCard.aerobicDecouplingPct·decouplingReading)

    /// 거리로 거르는 유형의 하한. GPS가 10km 코스를 9.8~9.9km로 재는 일이 흔해 10km를 고집하면
    /// 10km 대회 대부분이 빠진다. 사용자 경험값 — 출처 없음.
    static let decouplingMinDistanceM: Double = 9_500
    /// 이 기온 이상이면 후반 심박 상승을 더위 쪽으로 기울여 읽는다. 사용자 경험값 — 출처 없음.
    static let decouplingHotTempC: Double = 25

    /// 디커플링을 재는 러닝. 인터벌만 제외 — 회복 구간이 섞여 전·후반 비교가 성립하지 않는다.
    /// 롱런·LSD·거리주는 항상(분류기가 8km 이상을 보장), 그 외(대회·빌드업·템포·이지·일반)는 9.5km 이상.
    static func isDecouplingApplicable(workoutType wt: WorkoutType, distKm: Double) -> Bool {
        if wt == .interval { return false }
        if wt == .longRun || wt == .lsd || wt == .distanceRun { return true }
        return distKm * 1000 >= decouplingMinDistanceM
    }

    /// 전반·후반의 효율(속도 ÷ 심박) 차이(%). 양수 = 후반에 페이스 대비 심박이 올랐다(드리프트).
    /// 비율이라 후반에 페이스를 올리고 심박도 그만큼 오르면 상쇄된다 — 페이스 전략은 1차로 걸러진다.
    /// 1km 스플릿 기준, 심박 있는 온전한 스플릿이 6개 이상(반쪽 3km)일 때만.
    static func decouplingPct(splits: [SplitData], workoutType: WorkoutType, distKm: Double,
                              altitudeProfile: [(distanceKm: Double, altitude: Double)] = []) -> Double? {
        guard isDecouplingApplicable(workoutType: workoutType, distKm: distKm) else { return nil }
        // 초반 km 광학 오독은 뺀다 — 앞 절반 심박이 부풀어 −13%가 나왔다(실제 약 −0.5%, 2026-10-21)
        let full = splitsExcludingEarlyHRArtifact(splits, altitudeProfile: altitudeProfile).filter { $0.distanceM >= 900 && $0.avgHeartRate != nil }
        guard full.count >= 6 else { return nil }
        let half = full.count / 2
        func efficiency(_ part: ArraySlice<SplitData>) -> Double? {
            let dist  = part.reduce(0.0) { $0 + $1.distanceM }
            let dur   = part.reduce(0.0) { $0 + $1.duration }
            let hrSum = part.reduce(0.0) { $0 + Double($1.avgHeartRate ?? 0) * $1.duration }   // 시간 가중
            guard dur > 0, hrSum > 0 else { return nil }
            return (dist / dur) / (hrSum / dur)
        }
        guard let e1 = efficiency(full[..<half]), let e2 = efficiency(full[half...]), e1 > 0 else { return nil }
        return (e1 - e2) / e1 * 100
    }

    /// 구간별 뜻과 근거 — 숫자는 모두 보여주고, 문장만 유형·기온으로 갈라 읽는다.
    /// - ≤5%(음수 포함): 한 시간 안팎의 정상 드리프트 — 프릴(Friel) 코칭 경험칙. 검증된 진단 경계는 아니다.
    ///   출처: Friel, J. "Aerobic Endurance and Decoupling", TrainingPeaks Coach Blog, 2009.
    ///   https://www.trainingpeaks.com/coach-blog/aerobic-endurance-and-decoupling/
    ///   유산소 강도 러닝(롱런·LSD·이지·일반)에서만 "이 거리를 유산소로 감당" 판정을 붙인다.
    /// - 5~10%: 기반 부족과 더위·수분·초반 과속이 겹치는 모호 구간 — 기온(≥25°C)으로 기울여 읽는다.
    /// - >10%: 더위·탈수 조건에서 문헌이 보고하는 한 시간 드리프트 크기 안팎(Coyle & González-Alonso 2001,
    ///   Wingo 2005, Lafrenz 2008). 거친 기준점이지 검증된 경계는 아니다.
    /// - 빌드업: 후반 페이스를 올리는 훈련이라 심박이 따라 오르는 게 계획 — 판정 없이 그 사실만, 색도 중립.
    /// - 거리주·템포·대회: 강도가 높아 5% 규칙의 전제(유산소 강도)가 안 맞는다 — "유산소 기반" 대신
    ///   "이 페이스로 이 거리를 버틸 힘"으로 읽는다(드리프트 없이 그 강도를 끝까지 유지했다는 뜻).
    ///
    /// `lateHRRoseFirst` — 총평 "후반"이 심박 신호인지(`RunSummaryBuilder.lateHRRoseFirst`). pct ≤ 5일 때만 읽는다.
    /// shade: 카드 색 — 초록(.good)·흰색 0.85(.neutral)·주의색(.caution).
    /// isProblem: 5% 넘게 올랐고 덥지 않은 날(설계 P3). 빌드업은 계획이라 문제가 아니다.
    static func decouplingVerdict(pct: Double, workoutType wt: WorkoutType, temperatureC: Double?,
                                  lateHRRoseFirst: Bool, samePaceRise: FormNarrative.SamePaceHRRise? = nil) -> TabDigestRhythm.Verdict {
        let L = AppLanguage.shared
        let hot = (temperatureC ?? -.infinity) >= decouplingHotTempC
        typealias V = TabDigestRhythm.Verdict
        // 요약 개조식 — 같은 pct 값
        let p = String(format: "%.1f", pct)
        // 카드 차트 제목("디커플링")과 같은 이름 — 다른 화면의 '심박 드리프트'(전후반 심박 bpm 차)와 다른 지표다
        let drift = L.s("디커플링 \(p)%", "Decoupling \(p)%", ja: "デカップリング\(p)%")
        let heatTail = L.s(" · 더위 영향", " · heat", ja: " · 暑さの影響")
        if wt == .buildUp, samePaceRise != nil {
            // 같은 페이스 km끼리 심박이 8bpm↑ — "올린 만큼"이 아니다(FormNarrative.samePaceHRRise)
            return V(text: L.s("후반 페이스를 올린 것보다 심박이 더 올랐습니다.",
                               "HR rose more than the faster second half explains.", ja: "後半にペースを上げた分よりも心拍が上がりました。"),
                     isProblem: false, shade: .neutral,
                     short: L.s("후반 가속보다 심박 상승 큼 · \(p)%", "HR up more than the faster finish · \(p)%", ja: "後半の加速以上に心拍上昇 · \(p)%"))
        }
        if wt == .buildUp, pct < 0 {
            // 디커플링 음수 = 후반 효율이 더 좋았다 — "올린 만큼"보다 정확한 사실(2026-10-20, 5'26" 후반에 −1.4%)
            return V(text: L.s("후반 페이스를 올렸는데 심박은 그만큼 오르지 않았습니다.",
                               "Pace picked up late, but HR rose less than that.", ja: "後半にペースを上げましたが、心拍はその分ほど上がりませんでした。"),
                     isProblem: false, shade: .good,
                     short: L.s("후반 가속보다 심박 상승 작음 · \(p)%", "HR rose less than the faster finish · \(p)%", ja: "後半の加速ほど心拍は上がらず · \(p)%"))
        }
        if wt == .buildUp {
            return V(text: L.s("후반 페이스를 올린 만큼 심박도 올랐습니다.",
                               "HR rose with the faster second half.", ja: "後半にペースを上げた分、心拍も上がりました。"),
                     isProblem: false, shade: .neutral,
                     short: L.s("후반 가속만큼 심박 상승 · \(p)%", "HR up with faster finish · \(p)%", ja: "後半の加速分の心拍上昇 · \(p)%"))
        }
        let aerobic = wt == .longRun || wt == .lsd || wt == .easy || wt == .general
        // 전후반 5% 안이어도 총평 "후반"이 심박 신호면 "지켰다"고 하지 않는다 — 같은 화면에서 반대로 읽혔다
        if pct <= 5, lateHRRoseFirst {
            return V(text: L.s("전후반으로는 5% 안이지만, 마지막 구간에서 같은 페이스에 심박이 올랐습니다.",
                               "Within 5% half to half, but HR rose at the same pace in the final stretch.", ja: "前後半では5%以内ですが、最後の区間で同じペースでも心拍が上がりました。"),
                     isProblem: false, shade: .neutral,
                     short: L.s("마지막 구간 심박 상승 · 전후반 \(p)%", "HR up in the final stretch · \(p)% half to half", ja: "最後の区間で心拍上昇 · 前後半\(p)%"))
        }
        let within5 = drift + L.s(" · 5% 이내", " · within 5%", ja: " · 5%以内")
        if pct <= 5 {
            return aerobic
                ? V(text: L.s("후반까지 페이스 대비 심박을 지켰습니다. 이 거리를 유산소로 감당했습니다.",
                              "HR held against pace to the end — you covered this distance aerobically.", ja: "後半までペースに対する心拍を保ちました。この距離を有酸素でこなしました。"),
                    isProblem: false, shade: .good, short: within5)
                : V(text: L.s("후반까지 페이스 대비 심박을 지켰습니다. 이 페이스로 이 거리를 버틸 힘이 있습니다.",
                              "HR held against pace to the end — you can sustain this pace for this distance.", ja: "後半までペースに対する心拍を保ちました。このペースでこの距離を走りきる力があります。"),
                    isProblem: false, shade: .good, short: within5)
        }
        if pct <= 10 {
            return hot
                ? V(text: L.s("후반에 심박이 올랐지만 더운 날이라 자연스러운 범위입니다.",
                              "HR drifted up, but on a hot day that's within the normal range.", ja: "後半に心拍が上がりましたが、暑い日なので自然な範囲です。"),
                    isProblem: false, shade: .neutral, short: drift + heatTail)
                : V(text: L.s("조건은 좋았는데 후반에 심박이 올랐습니다. 이 거리와 강도가 아직 조금 부담일 수 있습니다.",
                              "Conditions were fine but HR drifted up — this distance and effort may still be a bit much.", ja: "条件はよかったのに後半に心拍が上がりました。この距離と強度はまだ少し負担なのかもしれません。"),
                    isProblem: true, shade: .neutral, short: drift)
        }
        return hot
            ? V(text: L.s("후반에 심박이 많이 올랐습니다. 더위와 수분 부족이 컸을 것입니다.",
                          "HR drifted a lot — heat and fluid loss likely played a big part.", ja: "後半に心拍が大きく上がりました。暑さと水分不足の影響が大きかったと考えられます。"),
                isProblem: false, shade: .caution, short: drift + heatTail)
            : V(text: L.s("후반에 심박이 많이 올랐습니다. 이 거리와 강도가 아직 버겁거나 초반이 빨랐을 수 있습니다.",
                          "HR drifted a lot — this may still be a stretch, or the start was too fast.", ja: "後半に心拍が大きく上がりました。この距離と強度がまだきついか、序盤が速かったのかもしれません。"),
                isProblem: true, shade: .caution, short: drift + L.s(" · 10% 초과", " · over 10%", ja: " · 10%超"))
    }

    // MARK: - 7일 부하 (옮김: PerformanceInsightCard.sevenDayLoadRatioLabel·sevenDayLoadSentence)

    /// "4주 평균 대비 낮음" — 7일 부하 / 4주 평균 비율 라벨.
    static func loadRatioText(_ ac: EffortLoad.RatioLabel) -> String {
        let L = AppLanguage.shared
        let t: String
        switch ac {
        case .low:      t = L.s("낮음", "lower", ja: "低い")
        case .steady:   t = L.s("유지", "steady", ja: "横ばい")
        case .high:     t = L.s("높음", "higher", ja: "高い")
        case .veryHigh: t = L.s("크게 높음", "much higher", ja: "大きく高い")
        }
        return L.s("지난 4주 대비 \(t)", "vs last 4 wks \(t)", ja: "直近4週比 \(t)")
    }

    /// 단조도 / 4주 평균 대비 문장 — "부상·위험" 표현 없음(Impellizzeri 2020).
    /// `SentenceKind`에는 '유지'가 없다(유지는 엔진이 nil로 침묵) — 반환형은 브리프 인터페이스대로 옵셔널이지만 지금은 늘 값이 있다.
    static func loadSentence(_ kind: EffortLoad.SentenceKind) -> String? {
        let L = AppLanguage.shared
        switch kind {
        // 라벨 뒤에 붙는 짧은 방향 문구 — 반폭 열에서 한 줄에 들어가야 한다
        case .monotony: return L.s("부하 편차 적음 — 강약 나누기", "little variation — split easy/hard", ja: "負荷の差が小さい — 強弱をつけましょう")
        case .veryHigh: return L.s("부하 크게 증가 중 — 회복 챙기기", "rising sharply — protect recovery", ja: "負荷が大きく増加中 — 回復を優先")
        case .high:     return L.s("부하 조금 높은 편", "slightly heavier than usual", ja: "負荷がやや高め")
        case .low:      return L.s("회복 방향으로 진행 중", "trending toward recovery", ja: "回復方向に進行中")
        }
    }

    /// 요약 개조식 — "강도 부하 4주 평균 대비 크게 높음 · 급증". 둘 다 없으면 nil.
    static func loadShort(ratio: EffortLoad.RatioLabel?, kind: EffortLoad.SentenceKind?) -> String? {
        let L = AppLanguage.shared
        let k: String? = kind.map {
            switch $0 {
            case .monotony: return L.s("편차 적음", "little variation", ja: "差が小さい")
            case .veryHigh: return L.s("급증", "surging", ja: "急増")
            case .high:     return L.s("조금 높은 편", "slightly heavy", ja: "やや高め")   // 라벨이 이미 '높음'이면 아래에서 뺀다
            case .low:      return L.s("감소", "easing", ja: "減少")
            }
        }
        // "4주 평균 대비 높음 · 조금 높은 편"은 같은 말 두 번 — 라벨이 높음·크게 높음이면 '조금 높은 편'은 뺀다(2026-10-18)
        let redundant = kind == .high && (ratio == .high || ratio == .veryHigh)
        let parts = [ratio.map(loadRatioText), redundant ? nil : k].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return L.s("강도 부하 ", "Training load ", ja: "強度負荷 ") + parts.joined(separator: " · ")  // 카드 차트 제목("강도 부하")과 같은 이름
    }

    /// 라벨과 문장을 카드와 같은 구분자로 잇는다 — 둘 다 없으면 nil.
    static func loadLine(ratio: String?, sentence: String?) -> String? {
        let parts = [ratio, sentence].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: AppLanguage.shared.s(", ", ", ", ja: "、"))
    }

    // MARK: - 이지 비율 알림 (옮김: PerformanceInsightCard.intensityColumnsView ② 회차 기준 K-7)

    /// "{w}주 {n}회 중 이지런 {k}회 · 이지런 없는 주 N주째" — 분류 12회 이상 · 이지런 비율 20% 미만일 때만. 아니면 nil.
    static func easyAlertText(weeks: Int, classified: Int, easyCount: Int, easyStreak w: Int, easyStreakAtLeast atLeast: Bool) -> String? {
        guard classified >= 12 && Double(easyCount) / Double(max(1, classified)) < 0.20 else { return nil }
        let L = AppLanguage.shared
        let streakSuffix: String = {
            guard w > 1 || (w == 1 && atLeast) else { return "" }
            return L.s(" · 이지런 없는 주 \(w)주\(atLeast ? " 이상" : "")째", " · \(w)\(atLeast ? "+" : "") wk in a row with none", ja: " · イージーランなしの週が\(w)週\(atLeast ? "以上" : "")連続")
        }()
        // 계획이 아니라 러닝 종류(이지런) 회차 — "N주째"가 무엇인지(이지런 없는 주) 밝힌다
        return L.s(
            "\(weeks)주 \(classified)회 중 이지런 \(easyCount)회\(streakSuffix)",
            "Easy runs: \(easyCount) of \(classified) in \(weeks) wk\(streakSuffix)", ja: "\(weeks)週\(classified)回のうちイージーラン\(easyCount)回\(streakSuffix)"
        )
    }

    // MARK: - 복귀 (옮김: PerformanceInsightCard.returnInsight·returnInsightRow·returnRecoveredRow)

    private struct ReturnInfo {
        let gapDays: Int
        /// 화면 표시용 원본 bpm — 판정/비교는 `returnInfo` 내부에서 보정값으로 이미 끝났다.
        let preGapHR: Double?
        let todayHR: Double?
        let isExpiredByTime: Bool
        let hrRecovered: Bool
    }

    private static func refHR(_ a: Activity, heatHRModel: MRHeatHRModel?) -> Double? {
        if let m = heatHRModel { return m.refHR(of: a) }
        return a.avgHeartRate.map(Double.init)
    }

    private static func returnInfo(activity: Activity, history: [Activity], heatHRModel: MRHeatHRModel?) -> ReturnInfo? {
        func refHR(_ a: Activity) -> Double? { Self.refHR(a, heatHRModel: heatHRModel) }
        guard activity.type == .running else { return nil }
        let cal = Calendar.current
        let sorted = history.filter { $0.type == .running }.sorted { $0.date < $1.date }
        guard let idx = sorted.firstIndex(where: { $0.id == activity.id }), idx > 0 else {
            #if DEBUG
            let runCount = history.filter { $0.type == .running }.count
            print("[복귀] 미발동: history 러닝 \(runCount)회, activity.id 찾기 실패 또는 첫 러닝")
            #endif
            return nil
        }

        let prev = sorted[idx - 1]
        let gapFromPrev = cal.dateComponents([.day], from: prev.date, to: activity.date).day ?? 0

        // ── 1번째 복귀 러닝: "N일 만의 러닝이에요" ───────────────────────────
        if gapFromPrev >= 14 {
            let preGapRuns = sorted.filter {
                $0.date < prev.date && $0.date >= prev.date.addingTimeInterval(-28 * 86_400)
            }
            // 15°C 기준 — 공백 전후가 계절을 넘는 경우가 많다. 화면 표시는 원본 bpm(preGapHRRaw),
            // 판정/비교는 보정값(preGapHRRef)을 쓴다 — 둘의 러닝 선택 기준(같은 페이스 우선)은 같다.
            let preGapSelected: [Activity]? = preGapRuns.count >= 3 ? {
                if let todayPace = activity.paceSecPerKm {
                    let matched = preGapRuns.filter {
                        guard let p = $0.paceSecPerKm else { return false }
                        return abs(p - todayPace) / todayPace <= 0.20
                    }
                    if matched.count >= 2, matched.contains(where: { $0.avgHeartRate != nil }) { return matched }
                }
                return preGapRuns
            }() : nil
            let preGapHRRaw: Double? = preGapSelected.flatMap { runs -> Double? in
                let hrs = runs.compactMap { $0.avgHeartRate }
                return hrs.isEmpty ? nil : Double(hrs.reduce(0, +)) / Double(hrs.count)
            }
            let daysSince = cal.dateComponents([.day], from: activity.date, to: Date()).day ?? 0
            #if DEBUG
            let preGapHRRef: Double? = preGapSelected.flatMap { runs -> Double? in
                let hrs = runs.compactMap { refHR($0) }
                return hrs.isEmpty ? nil : hrs.reduce(0, +) / Double(hrs.count)
            }
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let matchedCount: Int = {
                guard let todayPace = activity.paceSecPerKm else { return 0 }
                return preGapRuns.filter {
                    guard let p = $0.paceSecPerKm else { return false }
                    return abs(p - todayPace) / todayPace <= 0.20
                }.count
            }()
            print("[복귀] 직전 러닝 \(df.string(from: prev.date)) · 간격 \(gapFromPrev)일 (기준 14일) → 발동")
            print("[복귀] 공백 전 4주: 러닝 \(preGapRuns.count)회 · 같은 페이스 심박 \(matchedCount)회 · 공백 전 심박(보정) \(preGapHRRef.map { String(Int($0)) } ?? "없음")")
            if let today = refHR(activity) {
                if let pre = preGapHRRef {
                    let diff = Int(today.rounded()) - Int(pre.rounded())
                    print("[복귀] 오늘 심박(보정) \(Int(today.rounded())) vs 공백 전 \(Int(pre.rounded())) → \(diff >= 0 ? "+" : "")\(diff)bpm")
                } else {
                    print("[복귀] 오늘 심박(보정) \(Int(today.rounded())) · 공백 전 심박 없음 (공백 전 런 \(preGapRuns.count)회 < 3 or HR data 없음)")
                }
            } else {
                print("[복귀] 오늘 심박 없음")
            }
            #endif
            return ReturnInfo(
                gapDays: gapFromPrev,
                preGapHR: preGapHRRaw,
                todayHR: activity.avgHeartRate.map(Double.init),
                isExpiredByTime: daysSince >= 28,
                hrRecovered: false  // 첫 복귀 런에서는 심박 회복 메시지 절대 표시 안 함
            )
        }

        // ── 2회차 이상 복귀 러닝: "심박이 돌아왔어요" ──────────────────────
        // 최근 28일 안에 ≥14일 공백이 있었고, 그 복귀 후 2번째 이상 런인 경우에만 평가
        for i in stride(from: idx - 1, through: 1, by: -1) {
            let daysSinceI = cal.dateComponents([.day], from: sorted[i].date, to: activity.date).day ?? 0
            guard daysSinceI <= 28 else { break }
            let prevToI = cal.dateComponents([.day], from: sorted[i - 1].date, to: sorted[i].date).day ?? 0
            guard prevToI >= 14 else { continue }
            // sorted[i]가 첫 복귀 런 — activity는 2회차 이상
            let preGapEnd = sorted[i - 1]
            let preGapRuns = sorted.filter {
                $0.date < preGapEnd.date && $0.date >= preGapEnd.date.addingTimeInterval(-28 * 86_400)
            }
            guard preGapRuns.count >= 3 else { return nil }
            // 15°C 기준 — 공백 전후가 계절을 넘는 경우가 많다. 화면 표시는 원본 bpm(preGapHRRaw),
            // 판정/비교는 보정값(preGapHRRef)을 쓴다 — 둘의 러닝 선택 기준(같은 페이스 우선)은 같다.
            let preGapSelected: [Activity] = {
                if let todayPace = activity.paceSecPerKm {
                    let matched = preGapRuns.filter {
                        guard let p = $0.paceSecPerKm else { return false }
                        return abs(p - todayPace) / todayPace <= 0.20
                    }
                    if matched.count >= 2, matched.contains(where: { $0.avgHeartRate != nil }) { return matched }
                }
                return preGapRuns
            }()
            let preGapHRRaw: Double? = {
                let hrs = preGapSelected.compactMap { $0.avgHeartRate }
                return hrs.isEmpty ? nil : Double(hrs.reduce(0, +)) / Double(hrs.count)
            }()
            let preGapHRRef: Double? = {
                let hrs = preGapSelected.compactMap { refHR($0) }
                return hrs.isEmpty ? nil : hrs.reduce(0, +) / Double(hrs.count)
            }()
            guard let pre = preGapHRRef else { return nil }
            // 첫 복귀 런부터 현재까지 (2회 이상) — 심박 평균이 공백 전 대비 ≤+3bpm이면 회복 (보정값끼리 비교)
            let postRuns = sorted.filter { $0.date >= sorted[i].date && $0.date <= activity.date }
            guard postRuns.count >= 2 else { return nil }
            let postHRs = postRuns.compactMap { refHR($0) }
            guard !postHRs.isEmpty else { return nil }
            let postAvgHR = postHRs.reduce(0, +) / Double(postHRs.count)
            guard (postAvgHR - pre) <= 3 else { return nil }
            let daysSince = cal.dateComponents([.day], from: sorted[i].date, to: Date()).day ?? 0
            return ReturnInfo(
                gapDays: prevToI,
                preGapHR: preGapHRRaw,
                todayHR: activity.avgHeartRate.map(Double.init),
                isExpiredByTime: daysSince >= 28,
                hrRecovered: true
            )
        }
        return nil
    }

    /// 복귀 문장. 복귀가 아니면 nil.
    /// - 첫 복귀 러닝: gap("{g}일 만의 러닝입니다") + compare(공백 전 같은 페이스 심박 비교 · 더위 꼬리, 심박 둘 다 있을 때) + advice(공백 28일↑)
    /// - 2회차 이상, 심박 회복: recovered 문장. 이때 카드는 회복 줄만 그린다(gap 문장은 그 공백 일수로 채워 두지만 쓰지 않는다).
    static func returnSentences(activity: Activity, history: [Activity], heatHRModel: MRHeatHRModel?)
        -> (gap: String, compare: String?, advice: String?, recovered: String?)? {
        guard let ri = returnInfo(activity: activity, history: history, heatHRModel: heatHRModel) else { return nil }
        return returnSentences(ri, activity: activity, heatHRModel: heatHRModel)
    }

    /// 요약 개조식 — "21일 만의 러닝 · 공백 전 심박 142 → 오늘 151" / 회복 "심박 공백 전 수준 회복"
    private static func returnShort(_ ri: ReturnInfo) -> String {
        let L = AppLanguage.shared
        if ri.hrRecovered {
            return L.s("심박 공백 전 수준 회복", "HR back to pre-break level", ja: "心拍がブランク前の水準に回復")
        }
        let gap = L.s("\(ri.gapDays)일 만의 러닝", "First run in \(ri.gapDays) days", ja: "\(ri.gapDays)日ぶりのラン")
        guard let pre = ri.preGapHR, let today = ri.todayHR else { return gap }
        let a = Int(pre.rounded()), b = Int(today.rounded())
        return gap + L.s(" · 공백 전 심박 \(a) → 오늘 \(b)", " · HR \(a) before → \(b) today", ja: " · ブランク前の心拍\(a) → 今日\(b)")
    }

    private static func returnSentences(_ ri: ReturnInfo, activity: Activity, heatHRModel: MRHeatHRModel?)
        -> (gap: String, compare: String?, advice: String?, recovered: String?) {
        let L = AppLanguage.shared
        let gap = L.s("\(ri.gapDays)일 만의 러닝입니다", "First run in \(ri.gapDays) days", ja: "\(ri.gapDays)日ぶりのランです")
        if ri.hrRecovered {
            return (gap, nil, nil,
                    L.s("심박이 공백 전 수준으로 돌아왔습니다", "Your HR is back to pre-break levels", ja: "心拍がブランク前の水準に戻りました"))
        }
        var compare: String? = nil
        if let pre = ri.preGapHR, let today = ri.todayHR {
            let base = L.s("공백 전 같은 페이스에서 심박 \(Int(pre.rounded()))이었는데 오늘은 \(Int(today.rounded()))입니다",
                           "Pre-gap HR was \(Int(pre.rounded())) at this pace — today \(Int(today.rounded()))", ja: "ブランク前は同じペースで心拍\(Int(pre.rounded()))でしたが、今日は\(Int(today.rounded()))です")
            let heatSuffix: String = {
                guard let m = heatHRModel, m.explains(tempC: activity.temperatureC) else { return "" }
                let n = Int(m.delta(activity.temperatureC).rounded())
                return m.isFallback
                    ? L.s(" · 더위로 +\(n)bpm 정도", " · about +\(n) bpm from heat", ja: " · 暑さで+\(n)bpmほど")
                    : L.s(" · 더위로 +\(n)bpm", " · +\(n) bpm from heat", ja: " · 暑さで+\(n)bpm")
            }()
            compare = base + heatSuffix
        }
        let advice: String? = ri.gapDays >= 28
            ? L.s("체력이 돌아오는 데 보통 공백만큼의 시간이 걸립니다. 2~3주에 걸쳐 천천히 올려도 괜찮습니다",
                  "Fitness takes about as long as the break to return. Build back gradually over 2–3 weeks.", ja: "体力が戻るには通常ブランクと同じくらいの時間がかかります。2~3週間かけてゆっくり上げても大丈夫です")
            : nil
        return (gap, compare, advice, nil)
    }

    // MARK: - 퍼포먼스 블록 신호 (설계 §4.3)

    private static func line(_ axisLabel: String?, in lines: [RunSummaryLine]) -> RunSummaryLine? {
        guard let lbl = axisLabel else { return nil }
        return lines.first { $0.axis == lbl }
    }

    /// `easyAlertText` — 카드가 이미 계산한 이지 비율 알림(비동기 결과). 아직 없으면 nil → P5 건너뜀.
    static func signals(context c: RunSummaryBuilder.Context, input i: RunSummaryInput, lines: [RunSummaryLine],
                        insights: [RunInsight], easyAlertText: String?) -> [TabDigest.Signal] {
        var out: [TabDigest.Signal] = []
        let L = AppLanguage.shared
        func problem(_ p: Int, _ family: TabDigest.Family, _ text: String, _ direction: String?, short: String?) {
            out.append(TabDigest.Signal(tab: .performance, kind: .problem, priority: p, family: family, text: text,
                                        tone: .caution, direction: direction, short: short))
        }
        func good(_ p: Int, _ family: TabDigest.Family, _ text: String, short: String?) {
            out.append(TabDigest.Signal(tab: .performance, kind: .good, priority: p, family: family, text: text, tone: .good, short: short))
        }
        let loadNext = line(RunHeadline.Axis.load.label, in: lines)?.next

        // P1 — 복귀(공백 14일↑): "{g}일 만의 러닝입니다" + 공백 전 심박 비교, 방향 = 28일↑ 권고
        let ri = returnInfo(activity: c.activity, history: c.history, heatHRModel: c.heatHRModel)
        let ret = ri.map { returnSentences($0, activity: c.activity, heatHRModel: c.heatHRModel) }
        let retShort = ri.map(returnShort)
        if let r = ret, r.recovered == nil {
            let text = r.compare.map { r.gap + " — " + $0 } ?? r.gap
            problem(1, .unique, text, r.advice, short: retShort)
        }

        // P2 — 7일 부하 크게 증가 / 단조. 카드처럼 오늘 강도 입력 전이면 말하지 않는다(7일 합에 오늘이 빠짐).
        let jumped = i.acuteChronic == .high || i.acuteChronic == .veryHigh
        if !i.todayEffortMissing, jumped || i.loadSentence == .monotony,
           let line = loadLine(ratio: i.acuteChronic.map(loadRatioText), sentence: i.loadSentence.flatMap(loadSentence)) {
            // 요약(short)이 이미 "4주 평균 대비 높음"을 말한다 — 아랫줄은 같은 말 대신 근거 숫자(2026-10-18)
            let L = AppLanguage.shared
            let numbers: String? = {
                guard let recent = i.recentWeeklyAU, let avg = i.fourWeekAvgAU, avg > 0 else { return nil }
                let f = { (v: Double) in Int(v.rounded()).formatted(.number.grouping(.automatic)) }
                return L.s("최근 흐름 \(f(recent)) · 4주 흐름 \(f(avg)) (AU/주)", "recent \(f(recent)) · 4-wk trend \(f(avg)) (AU/wk)", ja: "最近の流れ \(f(recent)) · 4週の流れ \(f(avg)) (AU/週)")
            }()
            problem(2, .load, numbers ?? line, loadNext, short: loadShort(ratio: i.acuteChronic, kind: i.loadSentence))
        }

        // P3 — 디커플링. 값이 계산되면 .lateHR 신호를 정확히 1개 낸다(설계 §5: 후반 심박은 퍼포먼스 소유 — 리듬 R4가 다른 말을 하지 않게)
        //   문제: 5% 넘게 오름(덥지 않음) · 주의색(더운 날 10%↑ 포함) · 5% 안이지만 마지막 구간 심박 상승
        //   좋음 g3: 지켰다(초록) / 그 밖 중립(더운 날 5~10%, 빌드업): 덧붙임(extra, 1)·톤 중립
        let distKm = c.activity.distance / 1000
        if let pct = decouplingPct(splits: c.detail?.splits ?? [], workoutType: c.workoutType, distKm: distKm,
                                    altitudeProfile: c.detail?.altitudeProfile ?? []) {
            // 카드처럼 5% 안일 때만 총평 후반 심박 판정을 본다
            let lateFirst = pct <= 5 && RunSummaryBuilder.lateHRRoseFirst(activity: c.activity, detail: c.detail,
                                                                         workoutType: c.workoutType, history: c.history)
            let v = decouplingVerdict(pct: pct, workoutType: c.workoutType, temperatureC: c.activity.temperatureC,
                                      lateHRRoseFirst: lateFirst,
                                      samePaceRise: c.workoutType == .buildUp ? FormNarrative.samePaceHRRise(splits: c.detail?.splits ?? [], altitudeProfile: c.detail?.altitudeProfile ?? []) : nil)
            if v.isProblem || v.shade == .caution || lateFirst {
                problem(3, .lateHR, v.text, nil, short: v.short)
            } else if v.isGood {
                good(3, .lateHR, v.text, short: v.short)
            } else {
                // 중립(더운 날 5~10%·빌드업) — 덧붙임으로 항상 보인다(.lateHR을 가져가므로 리듬 R3/R4 사실이 사라지지 않게)
                out.append(TabDigest.Signal(tab: .performance, kind: .extra, priority: 1, family: .lateHR, text: v.text, tone: .neutral,
                                            short: v.short))
            }
        }

        // P4 — 같은 페이스 심박 높음(효율 비교, 카디악 드리프트 제외) / g1 낮음
        // 인사이트 highlights 첫 값 = 효율 "Nbpm" · 지구력 "N.N%" · 유산소 VO2 값(엔진이 채우는 순서)
        let eff = RunInsight.efficiencyComparison(in: insights)
        func effShort(lower: Bool) -> String {
            let h = eff?.highlights.first.map { " " + $0 } ?? ""
            return lower ? L.s("같은 페이스 심박\(h) 낮음", "HR\(h) lower at same pace", ja: "同ペースで心拍\(h)低い")
                         : L.s("같은 페이스 심박\(h) 높음", "HR\(h) higher at same pace", ja: "同ペースで心拍\(h)高い")
        }
        if let eff, eff.source == .efficiencyComparisonHigher { problem(4, .efficiency, eff.message, nil, short: effShort(lower: false)) }

        // P5 — 이지 비율 경고(카드 비동기 결과가 있을 때만) — 문장이 이미 개조식("8주 14회 중 이지런 2회 · …")
        if let t = easyAlertText { problem(5, .unique, t, loadNext, short: t) }

        // P6 — 후반 페이스 5%↑ 느려짐(지구력 인사이트 caution = 5% 초과). 문장 꼬리에 권고가 있다.
        let endurance = insights.first { $0.category == .endurance }
        let endDrift = endurance?.highlights.first.map { " " + $0 } ?? ""
        if let e = endurance, e.tone == .caution {
            problem(6, .latePace, e.message, nil,
                    short: L.s("후반 페이스\(endDrift) 느려짐", "Back half\(endDrift) slower", ja: "後半ペース\(endDrift)低下"))
        }

        // P7 — 유산소 등급 평균 이하·낮음(cardio 톤 neutral = belowAvg·low)
        if let cardio = insights.first(where: { $0.category == .cardio }), cardio.tone == .neutral {
            let vo = cardio.highlights.first.map { " " + $0 } ?? ""
            problem(7, .unique, cardio.message, nil,
                    short: L.s("유산소 피트니스\(vo) · \(cardio.badge)", "Cardio fitness\(vo) · \(cardio.badge)", ja: "心肺フィットネス\(vo) · \(cardio.badge)"))
        }

        // 좋은 신호 — 같은 페이스 심박 낮음 → (역치 상승은 제목이 말하므로 제외) → 디커플링 ≤5%(위 P3에서) → 복귀 심박 회복 → 후반 유지
        if let eff, eff.tone == .good { good(1, .efficiency, eff.message, short: effShort(lower: true)) }
        if let rec = ret?.recovered { good(4, .unique, rec, short: retShort) }
        // g5 — 전반 대비 후반 3% 안(네거티브 스플릿 포함). 카드의 '네거티브 스플릿'은 차트 꼬리표뿐이라 지구력 문장을 쓴다.
        if let e = endurance, e.tone == .good {
            good(5, .latePace, e.message,
                 short: L.s("후반 페이스 유지 · 전반 대비\(endDrift)", "Back half held · \(endDrift.trimmingCharacters(in: .whitespaces)) vs first half", ja: "後半ペース維持 · 前半比\(endDrift)"))
        }
        return out
    }

    /// 퍼포먼스 블록 기본 방향 — 훈련부하 줄의 next
    static func defaultDirection(lines: [RunSummaryLine]) -> String? {
        line(RunHeadline.Axis.load.label, in: lines)?.next
    }
}
