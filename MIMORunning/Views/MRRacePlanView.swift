import SwiftUI
import SwiftData

/// H:MM 형식 — 범위 표시용 (mrFormatDisplay보다 짧게)
private func mrFormatHM(_ minutes: Double) -> String {
    let total = Int(minutes.rounded())
    return "\(total / 60):\(String(format: "%02d", total % 60))"
}

private let mrAccent = Color(red: 0.48, green: 0.36, blue: 0.98)
private let mrCard   = Color(red: 0.11, green: 0.11, blue: 0.12)
private let mrGood   = Color(red: 0.30, green: 0.80, blue: 0.55)
private let mrWarn   = Color(red: 0.95, green: 0.68, blue: 0.25)

/// 플랜 빌드 시점에 한국어로 생성된 breakdown 문자열을 표시 시점에 번역.
/// 캐시된 플랜에도 적용되도록 view layer에서 처리한다.
private func localizedBreakdown(_ s: String) -> String {
    guard AppLanguage.shared.isEnglish else { return s }
    return s
        .replacingOccurrences(of: "롱런", with: "Long run")
        .replacingOccurrences(of: "이지", with: "Easy")
        .replacingOccurrences(of: "짧게", with: "Short")
        .replacingOccurrences(of: "강도는 그대로", with: "Keep the intensity")
        .replacingOccurrences(of: "마지막 ", with: "last ")
        .replacingOccurrences(of: "분은 ", with: " min at ")
        .replacingOccurrences(of: "회", with: "x")
        .replacingOccurrences(of: "× ", with: "× ")   // keep spacing
}

private func localizedPhase(_ p: String) -> String {
    let L = AppLanguage.shared
    switch p {
    case "늘리기":       return L.s("늘리기", "Build")
    case "유지":         return L.s("유지", "Maintain")
    case "회복":         return L.s("회복", "Recovery")
    case "테이퍼":       return L.s("테이퍼", "Taper")
    case "대회 페이스":  return L.s("대회 페이스", "Race pace")
    default:             return p
    }
}

// MARK: - 대회 하나

struct MRRacePlanCard: View {
    let check: MRGoalCheck
    var isExpanded: Bool = true
    /// 실제 러닝 기록 — 이행 기호 계산용
    var runs: [MRWorkout] = []
    /// 계획 시작 시점 스냅샷 — 이행 비교 기준
    var snapshot: RacePlanSnapshot? = nil
    var onToggleCollapse: (() -> Void)? = nil   // trailing closure 를 위해 마지막에
    @State private var showWeeks = false

    private var plan: MRRacePlan { check.plan }
    private var race: MRTargetRace { check.race }

    private var daysLeft: Int {
        Calendar.current.dateComponents([.day], from: Date(),
                                        to: race.date).day ?? 0
    }

    /// 목표와의 거리를 색으로. ⚠ 빨강을 쓰지 않는다.
    ///   빨강은 "틀렸다"로 읽힌다. 여기서 말하려는 건 거리감이지 판정이 아니다.
    private var gapColor: Color {
        guard let g = check.goalMin, let gap = check.gapMin else { return .white }
        let pct = gap / g * 100
        return pct <= 0 ? mrGood : (pct <= 3 ? mrAccent : mrWarn)
    }

    private func bridgeTextColor(_ text: String) -> Color {
        if text.hasPrefix("회복") { return Color(red: 0.35, green: 0.65, blue: 0.95) }
        if text.hasPrefix("유지") { return Color(red: 0.45, green: 0.80, blue: 0.55) }
        if text.hasPrefix("이 계획 시작") { return mrAccent }
        return .white.opacity(0.82)
    }

    var body: some View {
        let L = AppLanguage.shared
        if !isExpanded {
            MRRaceCollapsedRow(name: race.name, date: race.date,
                               weekCount: plan.weeks.count, onTap: onToggleCollapse ?? {})
        } else {
        VStack(alignment: .leading, spacing: 0) {

            // 헤더
            HStack(alignment: .firstTextBaseline) {
                Text(race.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(race.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(mrAccent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(mrAccent.opacity(0.15))
                    .clipShape(Capsule())
                if onToggleCollapse != nil {
                    Button(action: onToggleCollapse!) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.50))
                            .padding(.leading, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("D-\(daysLeft) · \(L.s("\(plan.weeks.count)주 계획", "\(plan.weeks.count)-week plan"))")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.60))
                .padding(.top, 3)

            if !plan.startNote.isEmpty {
                Text(plan.startNote)
                    .font(.system(size: 12))
                    .foregroundStyle(mrAccent.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }

            if !plan.bridgeRows.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(plan.bridgeRows.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 8) {
                            Text(plan.bridgeRows[i].range)
                                .foregroundStyle(.white.opacity(0.48))
                                .frame(minWidth: 110, maxWidth: 110, alignment: .leading)
                                .monospacedDigit()
                            Text(plan.bridgeRows[i].text)
                                .foregroundStyle(bridgeTextColor(plan.bridgeRows[i].text))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.system(size: 11))
                .padding(.top, 10)
            }

            // 지금 → 계획후
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.s("지금 나가면", "If I start now")).font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.60))
                    Text(mrFormatDisplay(plan.projectedNow))
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.s("계획대로 쌓으면", "On plan")).font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.60))
                    Text(mrFormatDisplay(plan.projectedFinal))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if plan.projectedFinalLo > 0 {
                        Text("(\(mrFormatHM(plan.projectedFinalLo)) ~ \(mrFormatHM(plan.projectedFinalHi)))")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                    } else if !plan.projectedFinalNote.isEmpty {
                        Text(plan.projectedFinalNote)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                Spacer()
            }
            .padding(.top, 16)

            // 목표 대비
            if let goal = check.goalMin, let gap = check.gapMin {
                HStack(spacing: 6) {
                    Text(L.s("목표 \(mrFormatDisplay(goal))", "Goal: \(mrFormatDisplay(goal))"))
                        .foregroundStyle(.white.opacity(0.68))
                    Text(gap <= 0
                         ? String(format: L.s("%.0f분 여유", "%.0f min ahead"), -gap)
                         : String(format: L.s("%.0f분 %02d초 모자람", "%.0f min %02d sec short"), floor(gap),
                                  Int((gap - floor(gap)) * 60)))
                        .foregroundStyle(gapColor)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 13))
                .padding(.top, 12)

                Text(check.verdict)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 레버 — 판정이 아니라 선택지다
            if !check.levers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(check.levers, id: \.self) { lv in
                        HStack(alignment: .top, spacing: 7) {
                            Circle().fill(mrAccent.opacity(0.5))
                                .frame(width: 4, height: 4).padding(.top, 6)
                            Text(lv).font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                    }
                }
                .padding(.top, 12)
            }

            // 롱런 진행 막대
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L.s("롱런", "Long run")).font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.60))
                    Spacer()
                    Text(String(format: "%.0f → %.0fkm",
                                plan.startingLongKm > 0 ? plan.startingLongKm : (plan.weeks.first?.longRunKm ?? 0),
                                plan.reachableLongKm))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(mrAccent)
                            .frame(width: g.size.width
                                   * min(plan.reachableLongKm / plan.targetLongKm, 1))
                    }
                }
                .frame(height: 5)
                // ⚠ 이 줄은 **롱런 준비**에 대한 것이지 목표 달성 여부가 아니다.
                //   "기록 목표 가능"이 목표 미달 문구 옆에 붙으면 모순으로 읽힌다.
                //   부족한 것이 준비인지 기간인지를 구분해서 말한다.
                Text({
                    switch plan.verdict {
                    case "기록 목표 가능":
                        return L.s("롱런 준비는 충분합니다", "Long run prep is sufficient")
                    case "완주는 충분, 기록은 다음 대회에":
                        return L.s("완주에는 충분한 롱런입니다", "Long run is enough for finishing")
                    default:
                        return L.s("이 기간에는 롱런을 여기까지 올릴 수 있습니다", "This is how far the long run can reach in this timeframe")
                    }
                }())
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.60))
            }
            .padding(.top, 18)

            // 주차별 계획 (접힘)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showWeeks.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(L.s(showWeeks ? "주차별 계획 접기" : "주차별 계획 보기", showWeeks ? "Collapse weekly plan" : "Show weekly plan"))
                    Image(systemName: showWeeks ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 12))
                .foregroundStyle(mrAccent)
            }
            .padding(.top, 16)

            if showWeeks {
                MRWeekTable(weeks: plan.weeks, histMaxWeeklyKm: plan.histMaxWeeklyKm,
                            runs: runs, snapshotWeeks: snapshot?.planWeeks ?? [])
                    .padding(.top, 12)
            }

            // 근거 — 숨기지 않는다
            ForEach(plan.notes, id: \.self) { n in
                Text(n).font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(mrCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } // end isExpanded
    }
}

// MARK: - 주차별 표

struct MRWeekTable: View {
    let weeks: [MRPlanWeek]
    var histMaxWeeklyKm: Double = 0
    /// 실제 러닝 기록 — 이행 기호 계산에 사용
    var runs: [MRWorkout] = []
    /// 스냅샷 주차 — 있으면 이 값이 단일 소스. 재계산 플랜 값을 무시하고 최초 계획을 표시한다.
    var snapshotWeeks: [MRPlanWeekSummary] = []
    @State private var expanded: Set<Int> = []

    private let dateFmt: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "M/d"
        return df
    }()

    // MARK: - 스냅샷 기반 헬퍼

    private func isCurrentSnap(_ snap: MRPlanWeekSummary) -> Bool {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let weekStart  = cal.startOfDay(for: snap.monday)
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return false }
        return todayStart >= weekStart && todayStart < weekEnd
    }

    /// 과거·현재 주의 실제 달린 거리. 미래 주는 nil.
    private func actualDataForSnap(_ snap: MRPlanWeekSummary) -> (long: Double, weekly: Double)? {
        let cal = Calendar.current
        let today     = cal.startOfDay(for: Date())
        let weekStart = cal.startOfDay(for: snap.monday)
        guard weekStart <= today else { return nil }
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return nil }
        let cutoff   = min(weekEnd, cal.date(byAdding: .day, value: 1, to: today) ?? weekEnd)
        let weekRuns = runs.filter { $0.start >= weekStart && $0.start < cutoff }
        let long   = weekRuns.compactMap(\.distanceKm).max() ?? 0
        let weekly = weekRuns.compactMap(\.distanceKm).reduce(0, +)
        return (long, weekly)
    }

    /// 지난 주만 기호 반환. 이번 주·미래 주 nil.
    private func complianceSymbolForSnap(_ snap: MRPlanWeekSummary) -> String? {
        let cal = Calendar.current
        let today     = cal.startOfDay(for: Date())
        let weekStart = cal.startOfDay(for: snap.monday)
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart),
              weekEnd <= today else { return nil }
        let weekRuns     = runs.filter { $0.start >= weekStart && $0.start < weekEnd }
        let actualLong   = weekRuns.compactMap(\.distanceKm).max() ?? 0
        let actualWeekly = weekRuns.compactMap(\.distanceKm).reduce(0, +)
        return weekSymbol(plan: snap, actualLong: actualLong, actualWeekly: actualWeekly)
    }

    /// 스냅샷 주의 예측 시간 — 재계산 플랜 주에서 날짜 매칭으로 조회.
    private func projectedMinForSnap(_ snap: MRPlanWeekSummary) -> Double? {
        let cal = Calendar.current
        let snapStart = cal.startOfDay(for: snap.monday)
        return weeks.first { cal.startOfDay(for: $0.monday) == snapStart }?.projectedMin
    }

    /// 스냅샷 주의 실행 안내 — 구버전 스냅샷(breakdown=="")은 라이브 플랜 주에서 폴백.
    private func breakdownForSnap(_ snap: MRPlanWeekSummary) -> String {
        let raw = snap.breakdown.isEmpty
            ? (weeks.first { Calendar.current.startOfDay(for: $0.monday) == Calendar.current.startOfDay(for: snap.monday) }?.breakdown ?? "")
            : snap.breakdown
        return localizedBreakdown(raw)
    }

    // MARK: - 라이브 플랜 헬퍼 (스냅샷 없을 때)

    private func isCurrent(_ w: MRPlanWeek) -> Bool {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let weekStart  = cal.startOfDay(for: w.monday)
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return false }
        return todayStart >= weekStart && todayStart < weekEnd
    }

    private func complianceSymbol(for w: MRPlanWeek) -> String? {
        let cal = Calendar.current
        let today     = cal.startOfDay(for: Date())
        let weekStart = cal.startOfDay(for: w.monday)
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart),
              weekEnd <= today else { return nil }
        guard let snap = snapshotWeeks.first(where: {
            cal.startOfDay(for: $0.monday) == weekStart
        }) else { return nil }
        let weekRuns     = runs.filter { $0.start >= weekStart && $0.start < weekEnd }
        let actualLong   = weekRuns.compactMap(\.distanceKm).max() ?? 0
        let actualWeekly = weekRuns.compactMap(\.distanceKm).reduce(0, +)
        return weekSymbol(plan: snap, actualLong: actualLong, actualWeekly: actualWeekly)
    }

    private func actualData(for w: MRPlanWeek) -> (long: Double, weekly: Double)? {
        let cal = Calendar.current
        let today     = cal.startOfDay(for: Date())
        let weekStart = cal.startOfDay(for: w.monday)
        guard weekStart <= today else { return nil }
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return nil }
        let cutoff = min(weekEnd, cal.date(byAdding: .day, value: 1, to: today) ?? weekEnd)
        let weekRuns = runs.filter { $0.start >= weekStart && $0.start < cutoff }
        let long   = weekRuns.compactMap(\.distanceKm).max() ?? 0
        let weekly = weekRuns.compactMap(\.distanceKm).reduce(0, +)
        return (long, weekly)
    }

    // MARK: - 공통

    private var complianceSummary: String? {
        let L = AppLanguage.shared
        let syms: [String]
        if !snapshotWeeks.isEmpty {
            syms = snapshotWeeks.compactMap { complianceSymbolForSnap($0) }
        } else {
            syms = weeks.compactMap { complianceSymbol(for: $0) }
        }
        guard !syms.isEmpty else { return nil }
        let both = syms.filter { $0 == symbolBoth }.count
        let one  = syms.filter { $0 == symbolOne  }.count
        let none = syms.filter { $0 == symbolNone }.count
        let over = syms.filter { $0 == symbolOver }.count
        var parts: [String] = []
        if over > 0 { parts.append("\(symbolOver) \(over)") }
        if both > 0 { parts.append("\(symbolBoth) \(both)") }
        if one  > 0 { parts.append("\(symbolOne) \(one)")  }
        if none > 0 { parts.append("\(symbolNone) \(none)") }
        let n = syms.count
        return L.s("지난 \(n)주:", "Last \(n) wks:") + " \(parts.joined(separator: " · "))"
    }

    private func phaseColor(_ p: String) -> Color {
        switch p {
        case "테이퍼":      return mrAccent
        case "회복":        return Color(red: 0.35, green: 0.65, blue: 0.95)
        case "대회 페이스": return mrWarn
        case "유지":        return Color(red: 0.45, green: 0.80, blue: 0.55)
        default:            return .white.opacity(0.82)
        }
    }

    private var legendItems: [(phase: String, desc: String)] {
        let L = AppLanguage.shared
        let present = snapshotWeeks.isEmpty
            ? Set(weeks.map(\.phase))
            : Set(snapshotWeeks.map(\.phase))
        return [
            (phase: "늘리기",       desc: L.s("롱런을 매주 조금씩 늘립니다",                              "Gradually increase long run each week")),
            (phase: "유지",         desc: L.s("롱런을 더 늘리지 않고 그 거리에 익숙해집니다",            "Get comfortable at the current long run distance")),
            (phase: "대회 페이스",   desc: L.s("롱런 안에 대회 페이스로 달리는 구간이 들어갑니다",        "Includes race-pace segments within the long run")),
            (phase: "회복",         desc: L.s("롱런과 주간 거리를 줄입니다. 몸은 쉴 때 좋아집니다",     "Reduce long run and weekly distance. Bodies improve with rest")),
            (phase: "테이퍼",       desc: L.s("대회 전 2주, 거리를 절반 이하로 줄입니다",               "2 weeks before race, cut volume below half")),
        ].filter { present.contains($0.phase) }
    }

    // MARK: - Body

    private func autoExpandCurrent() {
        guard expanded.isEmpty else { return }
        if !snapshotWeeks.isEmpty {
            // 이번 주와 다음 주 자동 펼침
            for (i, snap) in snapshotWeeks.enumerated() {
                if isCurrentSnap(snap) {
                    expanded.insert(snap.idx)
                    if i + 1 < snapshotWeeks.count {
                        expanded.insert(snapshotWeeks[i + 1].idx)
                    }
                    break
                }
            }
            // 이번 주가 없으면(미래 계획) 첫 주 펼침
            if expanded.isEmpty, let first = snapshotWeeks.first {
                expanded.insert(first.idx)
            }
        } else {
            for (i, w) in weeks.enumerated() {
                if isCurrent(w) {
                    expanded.insert(w.idx)
                    if i + 1 < weeks.count {
                        expanded.insert(weeks[i + 1].idx)
                    }
                    break
                }
            }
            if expanded.isEmpty, let first = weeks.first {
                expanded.insert(first.idx)
            }
        }
    }

    var body: some View {
        let L = AppLanguage.shared
        VStack(spacing: 0) {
            HStack {
                Text(L.s("주", "Wk")).frame(width: 36, alignment: .leading)
                Text(L.s("날짜", "Date")).frame(width: 40, alignment: .leading)
                Text(L.s("단계", "Phase")).frame(width: 64, alignment: .leading)
                Text(L.s("롱런", "Long")).frame(maxWidth: .infinity, alignment: .trailing)
                Text(L.s("주간", "Weekly")).frame(maxWidth: .infinity, alignment: .trailing)
                Text(L.s("예상", "Target")).frame(width: 56, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.bottom, 8)

            if !snapshotWeeks.isEmpty {
                // ── 스냅샷 기반 표시 ───────────────────────────────────────
                // 최초 계획 등록 시점의 주차 데이터를 단일 소스로 사용.
                // 이후 플랜 재계산으로 수치가 바뀌어도 이 값은 변하지 않는다.
                ForEach(snapshotWeeks, id: \.idx) { snap in
                    let isCurr     = isCurrentSnap(snap)
                    let sym        = complianceSymbolForSnap(snap)
                    let actual     = actualDataForSnap(snap)
                    let projMin    = projectedMinForSnap(snap)
                    let longOver   = actual.map { $0.long   > snap.longRunKm * 1.05 } ?? false
                    let weeklyOver = actual.map { $0.weekly > snap.weeklyKm  * 1.05 } ?? false

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            HStack(spacing: 0) {
                                Text(sym ?? "")
                                    .frame(width: 14, alignment: .leading)
                                    .foregroundStyle(.white.opacity(0.78))
                                Text("\(snap.idx)")
                                    .frame(width: 22, alignment: .leading)
                                    .foregroundStyle(isCurr ? .white : .white.opacity(0.72))
                                    .fontWeight(isCurr ? .semibold : .regular)
                            }
                            .frame(width: 36, alignment: .leading)
                            Text(dateFmt.string(from: snap.monday))
                                .frame(width: 40, alignment: .leading)
                                .foregroundStyle(isCurr ? .white.opacity(0.92) : .white.opacity(0.72))
                                .monospacedDigit()
                            Text(localizedPhase(snap.phase))
                                .frame(width: 64, alignment: .leading)
                                .foregroundStyle(phaseColor(snap.phase))
                            Text(String(format: "%.1f", snap.longRunKm))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .foregroundStyle(.white.opacity(0.85))
                            Text(String(format: "%.0f", snap.weeklyKm))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .foregroundStyle(.white.opacity(0.82))
                            Group {
                                if let pm = projMin {
                                    Text(mrFormatDisplay(pm))
                                        .foregroundStyle(.white.opacity(0.82))
                                } else {
                                    Text("—").foregroundStyle(.white.opacity(0.65))
                                }
                            }
                            .frame(width: 56, alignment: .trailing)
                        }
                        .font(.system(size: 12, design: .rounded))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.18)) {
                                if expanded.contains(snap.idx) { expanded.remove(snap.idx) }
                                else { expanded.insert(snap.idx) }
                            }
                        }

                        if expanded.contains(snap.idx) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 12) {
                                    HStack(spacing: 3) {
                                        Text(L.s("롱런", "Long")).foregroundStyle(.white.opacity(0.72))
                                        if let a = actual {
                                            Text(String(format: "%.1f", a.long))
                                                .fontWeight(.semibold).foregroundStyle(.white)
                                            if longOver { Text(symbolOver).foregroundStyle(.white.opacity(0.85)) }
                                        } else {
                                            Text("—").foregroundStyle(.white.opacity(0.65))
                                        }
                                        Text(String(format: "/%.1fkm", snap.longRunKm))
                                            .foregroundStyle(mrAccent.opacity(0.75))
                                    }
                                    HStack(spacing: 3) {
                                        Text(L.s("주간", "Weekly")).foregroundStyle(.white.opacity(0.72))
                                        if let a = actual {
                                            Text(String(format: "%.1f", a.weekly))
                                                .fontWeight(.semibold).foregroundStyle(.white)
                                            if weeklyOver { Text(symbolOver).foregroundStyle(.white.opacity(0.85)) }
                                        } else {
                                            Text("—").foregroundStyle(.white.opacity(0.65))
                                        }
                                        Text(String(format: "/%.0fkm", snap.weeklyKm))
                                            .foregroundStyle(mrAccent.opacity(0.75))
                                    }
                                    if isCurr {
                                        Text(L.s("진행 중", "In progress"))
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(mrAccent.opacity(0.88))
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(mrAccent.opacity(0.12), in: Capsule())
                                    }
                                }
                                .font(.system(size: 11, design: .rounded))
                                let bd = breakdownForSnap(snap)
                                if !bd.isEmpty {
                                    Text(bd)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.60))
                                }
                            }
                            .padding(.leading, 36).padding(.bottom, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.vertical, 5)
                    .background(isCurr ? .white.opacity(0.05) : .clear)
                }
            } else {
                // ── 라이브 플랜 표시 (스냅샷 없을 때) ──────────────────────
                ForEach(weeks, id: \.idx) { w in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            HStack(spacing: 0) {
                                Text(complianceSymbol(for: w) ?? "")
                                    .frame(width: 14, alignment: .leading)
                                    .foregroundStyle(.white.opacity(0.78))
                                Text("\(w.idx)")
                                    .frame(width: 22, alignment: .leading)
                                    .foregroundStyle(isCurrent(w) ? .white : .white.opacity(0.72))
                                    .fontWeight(isCurrent(w) ? .semibold : .regular)
                            }
                            .frame(width: 36, alignment: .leading)
                            Text(dateFmt.string(from: w.monday))
                                .frame(width: 40, alignment: .leading)
                                .foregroundStyle(isCurrent(w) ? .white.opacity(0.92) : .white.opacity(0.72))
                                .monospacedDigit()
                            Text(localizedPhase(w.phase))
                                .frame(width: 64, alignment: .leading)
                                .foregroundStyle(phaseColor(w.phase))
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.1f", w.longRunKm))
                                    .foregroundStyle(w.isNewMax ? .white : .white.opacity(0.85))
                                    .fontWeight(w.isNewMax ? .semibold : .regular)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(String(format: "%.0f", w.weeklyKm))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .foregroundStyle(.white.opacity(0.82))
                            Text(mrFormatDisplay(w.projectedMin))
                                .frame(width: 56, alignment: .trailing)
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        .font(.system(size: 12, design: .rounded))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.18)) {
                                if expanded.contains(w.idx) { expanded.remove(w.idx) }
                                else { expanded.insert(w.idx) }
                            }
                        }

                        if w.isVolRecord && histMaxWeeklyKm > 0 {
                            Text(L.s("└ 지난 1년 최고치(\(Int(histMaxWeeklyKm.rounded()))km)에 도달", "└ Reached 1-yr high (\(Int(histMaxWeeklyKm.rounded())) km)"))
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.65))
                                .padding(.leading, 64).padding(.bottom, 2)
                        }

                        if expanded.contains(w.idx) {
                            let actual     = actualData(for: w)
                            let longOver   = actual.map { $0.long   > w.longRunKm * 1.05 } ?? false
                            let weeklyOver = actual.map { $0.weekly > w.weeklyKm  * 1.05 } ?? false
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 12) {
                                    HStack(spacing: 3) {
                                        Text(L.s("롱런", "Long")).foregroundStyle(.white.opacity(0.72))
                                        if let a = actual {
                                            Text(String(format: "%.1f", a.long))
                                                .fontWeight(.semibold).foregroundStyle(.white)
                                            if longOver { Text(symbolOver).foregroundStyle(.white.opacity(0.85)) }
                                        } else {
                                            Text("—").foregroundStyle(.white.opacity(0.65))
                                        }
                                        Text(String(format: "/%.1fkm", w.longRunKm))
                                            .foregroundStyle(mrAccent.opacity(0.75))
                                    }
                                    HStack(spacing: 3) {
                                        Text(L.s("주간", "Weekly")).foregroundStyle(.white.opacity(0.72))
                                        if let a = actual {
                                            Text(String(format: "%.1f", a.weekly))
                                                .fontWeight(.semibold).foregroundStyle(.white)
                                            if weeklyOver { Text(symbolOver).foregroundStyle(.white.opacity(0.85)) }
                                        } else {
                                            Text("—").foregroundStyle(.white.opacity(0.65))
                                        }
                                        Text(String(format: "/%.0fkm", w.weeklyKm))
                                            .foregroundStyle(mrAccent.opacity(0.75))
                                    }
                                    if isCurrent(w) {
                                        Text(L.s("진행 중", "In progress"))
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(mrAccent.opacity(0.88))
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(mrAccent.opacity(0.12), in: Capsule())
                                    }
                                }
                                .font(.system(size: 11, design: .rounded))
                                if !w.breakdown.isEmpty {
                                    Text(localizedBreakdown(w.breakdown))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.60))
                                }
                            }
                            .padding(.leading, 36).padding(.bottom, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.vertical, 5)
                    .background(
                        w.isNewMax
                        ? mrAccent.opacity(0.07)
                        : (isCurrent(w) ? .white.opacity(0.05) : .clear)
                    )
                }
            }

            if let summary = complianceSummary {
                Text(summary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(L.s("행 탭 → 실제 기록 또는 실행 안내 · 진한 주 번호 = 이번 주 · 거리는 이지 페이스 기준", "Tap row → actual log or guidance · Bold = current week · Distance at easy pace"))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(L.s("● 둘 다 달성  ◐ 하나만 달성  ○ 미달성  ▲ 10% 초과", "● Both met  ◐ One met  ○ Not met  ▲ 10% over"))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 범례
            VStack(alignment: .leading, spacing: 5) {
                ForEach(legendItems, id: \.phase) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Text(localizedPhase(item.phase))
                            .foregroundStyle(phaseColor(item.phase))
                            .frame(width: 68, alignment: .leading)
                        Text(item.desc)
                            .foregroundStyle(.white.opacity(0.60))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 10))
                }
            }
            .padding(.top, 8)
        }
        .onAppear { autoExpandCurrent() }
    }
}

// MARK: - 목표끼리

struct MRGoalLinksView: View {
    let links: [MRGoalLink]

    // ⚠ 다 맞으면 그리지 않는다.
    //   "문제 없습니다"를 말하려고 카드를 쓰지 않는다 —
    //   묻지도 않은 질문에 답하는 셈이 된다.
    private var problems: [MRGoalLink] { links.filter { !$0.inRange } }

    var body: some View {
        if !problems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("목표 하나가 나머지와 어긋나 있습니다")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                // 어긋난 것만 보여준다. 맞는 것까지 나열할 이유가 없다.
                ForEach(problems, id: \.name) { l in
                    HStack {
                        Text(l.name).font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.78))
                        Spacer()
                        Text(l.note).font(.system(size: 12))
                            .foregroundStyle(l.isImpossible ? mrWarn : mrAccent)
                    }
                }

                // 병목이 어느 목표인지 짚어준다 — 이게 이 카드의 존재 이유다.
                if let bottleneck = bottleneckName {
                    Text("\(bottleneck) 목표를 조정하시면 나머지 둘과 맞아떨어집니다.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(mrCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    /// 세 관계 중 두 개에 등장하는 거리가 병목이다.
    private var bottleneckName: String? {
        var count: [String: Int] = [:]
        for p in problems {
            for part in p.name.components(separatedBy: " → ") {
                count[part.trimmingCharacters(in: .whitespaces), default: 0] += 1
            }
        }
        return count.filter { $0.value >= 2 }.max { $0.value < $1.value }?.key
    }
}

// MARK: - 계획 없는 임박 대회 카드

struct MRPlanlessRaceCard: View {
    let race: MRTargetRace
    @EnvironmentObject private var engine: MREngineStore

    // 플래너와 동일한 계산식 — 정수 나눗셈으로 주 수를 구한다.
    private var weeksToRace: Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: Date()),
                                      to:   cal.startOfDay(for: race.date)).day ?? 0
        return max(days / 7, 0)
    }

    private var raceTemp: Double {
        mrSeasonalTemp(runs: engine.runs, for: race.date) ?? MR_REF_TEMP
    }

    private var prediction: MRPrediction? {
        // ⚠ engine.predictions는 표준 조건(15°C) 값이다.
        //   8월 대회에 그대로 쓰면 실제보다 빠르게 나온다.
        mrPredict(efforts: engine.efforts, fit: engine.fit,
                  profile: engine.profile, heat: engine.heat,
                  asOf: Date(), targetTempC: raceTemp)
            .first { abs($0.distanceM - race.distanceM) / race.distanceM < 0.02 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(race.name).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(race.label).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(mrAccent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(mrAccent.opacity(0.15)).clipShape(Capsule())
            }
            if weeksToRace < 3 {
                // ⚠ 3주 미만은 훈련으로 바꿀 수 있는 게 없다.
                Text("대회가 가까워 훈련 계획을 세우지 않습니다. 지금부터는 쌓기보다 아끼는 편이 낫습니다.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // 기간은 충분하지만 기록 또는 훈련량 부족으로 계획 생성 불가.
                Text("아직 기록이 충분하지 않아 계획을 세우기 어렵습니다.\n몇 번 더 뛰고 나면 여기에 나타납니다.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let p = prediction {
                Text("지금 상태로 \(mrFormatDisplay(p.midMin)) 정도입니다")
                    .font(.system(size: 14)).foregroundStyle(.white)
                    .padding(.top, 2)
                Text(String(format: "대회 날 기온을 %.0f°C로 봤습니다 (예년 이맘때 본인 러닝 기준)", raceTemp))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(mrCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - '나' 탭에 넣을 묶음

struct MRRacePlanSection: View {
    @EnvironmentObject var engine: MREngineStore
    @Query private var snapshots: [RacePlanSnapshot]
    // 가장 가까운 대회 하나만 기본 펼침. nil이면 전체 접힘
    @State private var expandedId: String? = nil

    private func snapshot(for check: MRGoalCheck) -> RacePlanSnapshot? {
        let key = mrArchiveKey(raceDate: check.race.date, distanceM: check.race.distanceM)
        return snapshots.first { mrArchiveKey(raceDate: $0.raceDate, distanceM: $0.distanceM) == key }
    }

    var body: some View {
        VStack(spacing: 14) {
            if case .ready = engine.state {
                if engine.raceItems.isEmpty && !engine.userInput.races.isEmpty {
                    Text("아직 예상 기록을 낼 만한 기록이 부족합니다.\n대회에 준하는 노력이 몇 번 쌓이면 여기에 나타납니다.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(28)
                }
                MRGoalLinksView(links: mrGoalLinks(engine.userInput.goals))
                ForEach(engine.raceItems) { item in
                    let isExpanded = expandedId == item.id
                    switch item {
                    case .planned(let c):
                        MRRacePlanCard(check: c, isExpanded: isExpanded,
                                       runs: engine.runs, snapshot: snapshot(for: c)) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                expandedId = isExpanded ? nil : item.id
                            }
                        }
                    case .planless(let r):
                        if isExpanded {
                            MRPlanlessRaceCard(race: r)
                        } else {
                            MRRaceCollapsedRow(name: r.name, date: r.date, weekCount: nil) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    expandedId = item.id
                                }
                            }
                        }
                    }
                }
            } else if case .loading = engine.state {
                ProgressView().tint(.white).frame(height: 80)
            }
        }
        .onAppear {
            // 처음 또는 아이템이 바뀌었을 때 — 가장 가까운 대회를 기본 펼침
            if expandedId == nil || !engine.raceItems.map(\.id).contains(expandedId ?? "") {
                expandedId = engine.raceItems.first?.id
            }
        }
        .onChange(of: engine.raceItems.map(\.id)) { _, ids in
            if let curr = expandedId, ids.contains(curr) { return }
            expandedId = ids.first
        }
    }
}

// MARK: - 접힌 행

private struct MRRaceCollapsedRow: View {
    let name: String
    let date: Date
    let weekCount: Int?
    let onTap: () -> Void

    private var daysLeft: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("D-\(daysLeft)")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(mrAccent)
                        if let w = weekCount {
                            Text("· \(AppLanguage.shared.s("\(w)주", "\(w) wks"))")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.60))
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.50))
            }
            .padding(16)
            .background(mrCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 프리뷰

private func _previewGoalCheck() -> MRGoalCheck {
    let race = MRTargetRace(
        date: Calendar.current.date(byAdding: .weekOfYear, value: 32, to: Date())!,
        distanceM: MRDistance.dF, name: "JTBC 마라톤"
    )
    var plan = MRRacePlan(raceDate: race.date, distanceM: MRDistance.dF)
    plan.projectedNow     = 4 * 60 + 27
    plan.projectedFinal   = 4 * 60 + 7.4
    plan.projectedFinalLo = 4 * 60 + 1.5
    plan.projectedFinalHi = 4 * 60 + 13.8
    plan.reachableLongKm  = 22.0
    plan.targetLongKm     = 28.0
    plan.peakWeeklyKm     = 48.3
    plan.histMaxWeeklyKm  = 39.1
    plan.verdict = "완주는 충분, 기록은 다음 대회에"
    return MRGoalCheck(
        race: race, plan: plan,
        goalMin: 4 * 60, gapMin: 7.4,
        verdict: "조금 모자랍니다. 아래를 바꾸면 메워집니다",
        levers: ["롱런 25km → 4:03:12 ⚠ 32주로는 도달 불가 · 2027 서울마라톤에서는 가능"]
    )
}

private func _previewWeeks() -> [MRPlanWeek] {
    let cal = Calendar.current
    return (1...8).map { i in
        let mon = cal.date(byAdding: .weekOfYear, value: i, to: Date())!
        var w = MRPlanWeek(
            idx: i, monday: mon,
            phase: i > 6 ? "테이퍼" : (i % 4 == 0 ? "회복" : (Double(i) > 6 * 0.75 ? "대회 페이스" : "늘리기")),
            longRunKm: Double(10 + i), longRunMin: Double(70 + i * 5),
            weeklyKm: Double(30 + i * 3),
            projectedMin: 4 * 60 + 18 - Double(i) * 1.5,
            isNewMax: i == 3
        )
        w.isVolRecord = (i == 5)
        w.breakdown = String(format: AppLanguage.shared.s("롱런 %.0fkm + 이지 7km × 3회", "Long run %.0fkm + Easy 7km × 3x"), Double(10 + i))
        return w
    }
}

#Preview("플랜 카드 — 예측 범위") {
    MRRacePlanCard(check: _previewGoalCheck())
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("주차 표 — 과거 최대 초과 표시") {
    ScrollView { MRWeekTable(weeks: _previewWeeks(), histMaxWeeklyKm: 39.1).padding() }
        .background(Color.black).preferredColorScheme(.dark)
}
