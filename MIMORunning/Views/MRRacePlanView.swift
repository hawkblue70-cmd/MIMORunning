import SwiftUI

private let mrAccent = Color(red: 0.48, green: 0.36, blue: 0.98)
private let mrCard   = Color(red: 0.11, green: 0.11, blue: 0.12)
private let mrGood   = Color(red: 0.30, green: 0.80, blue: 0.55)
private let mrWarn   = Color(red: 0.95, green: 0.68, blue: 0.25)

// MARK: - 대회 하나

struct MRRacePlanCard: View {
    let check: MRGoalCheck
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

    var body: some View {
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
            }
            Text("D-\(daysLeft) · \(plan.weeks.count)주 남음")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 3)

            // 지금 → 계획후
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("지금 나가면").font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(mrFormatDisplay(plan.projectedNow))
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.top, 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text("계획대로 쌓으면").font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(mrFormatDisplay(plan.projectedFinal))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            .padding(.top, 16)

            // 목표 대비
            if let goal = check.goalMin, let gap = check.gapMin {
                HStack(spacing: 6) {
                    Text("목표 \(mrFormatDisplay(goal))")
                        .foregroundStyle(.white.opacity(0.5))
                    Text(gap <= 0
                         ? String(format: "%.0f분 여유", -gap)
                         : String(format: "%.0f분 %02d초 모자람", floor(gap),
                                  Int((gap - floor(gap)) * 60)))
                        .foregroundStyle(gapColor)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 13))
                .padding(.top, 12)

                Text(check.verdict)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
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
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                }
                .padding(.top, 12)
            }

            // 롱런 진행 막대
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("롱런").font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Text(String(format: "%.0f → %.0fkm",
                                plan.weeks.first?.longRunKm ?? 0,
                                plan.reachableLongKm))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
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
                        return "롱런 준비는 충분합니다"
                    case "완주는 충분, 기록은 다음 대회에":
                        return "완주에는 충분한 롱런입니다"
                    default:
                        return "이 기간에는 롱런을 여기까지 올릴 수 있습니다"
                    }
                }())
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.top, 18)

            // 주차별 계획 (접힘)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showWeeks.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(showWeeks ? "주차별 계획 접기" : "주차별 계획 보기")
                    Image(systemName: showWeeks ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 12))
                .foregroundStyle(mrAccent)
            }
            .padding(.top, 16)

            if showWeeks {
                MRWeekTable(weeks: plan.weeks).padding(.top, 12)
            }

            // 근거 — 숨기지 않는다
            ForEach(plan.notes, id: \.self) { n in
                Text(n).font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(mrCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - 주차별 표

struct MRWeekTable: View {
    let weeks: [MRPlanWeek]
    @State private var expanded: Set<Int> = []

    private func phaseColor(_ p: String) -> Color {
        switch p {
        case "테이퍼": return mrAccent
        case "회복":   return Color(red: 0.35, green: 0.65, blue: 0.95)
        default:       return .white.opacity(0.5)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("주").frame(width: 26, alignment: .leading)
                Text("단계").frame(width: 44, alignment: .leading)
                Text("롱런").frame(maxWidth: .infinity, alignment: .trailing)
                Text("주간").frame(maxWidth: .infinity, alignment: .trailing)
                Text("예상").frame(width: 62, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
            .padding(.bottom, 8)

            ForEach(weeks, id: \.idx) { w in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("\(w.idx)")
                            .frame(width: 26, alignment: .leading)
                            .foregroundStyle(.white.opacity(0.4))
                        Text(w.phase)
                            .frame(width: 44, alignment: .leading)
                            .foregroundStyle(phaseColor(w.phase))
                        // ⚠ 새 최장 롱런을 세우는 주는 표시해 준다.
                        //   Frandsen 2025의 참조 밴드(10%) 안에서만 세운다.
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1f", w.longRunKm))
                                .foregroundStyle(w.isNewMax ? .white : .white.opacity(0.6))
                                .fontWeight(w.isNewMax ? .semibold : .regular)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(String(format: "%.0f", w.weeklyKm))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .foregroundStyle(.white.opacity(0.5))
                        Text(mrFormatDisplay(w.projectedMin))
                            .frame(width: 62, alignment: .trailing)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .font(.system(size: 12, design: .rounded))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !w.breakdown.isEmpty else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            if expanded.contains(w.idx) { expanded.remove(w.idx) }
                            else { expanded.insert(w.idx) }
                        }
                    }

                    if expanded.contains(w.idx) && !w.breakdown.isEmpty {
                        Text(w.breakdown)
                            .font(.system(size: 11))
                            .foregroundStyle(mrAccent.opacity(0.85))
                            .padding(.leading, 70)
                            .padding(.bottom, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.vertical, 5)
                .background(w.isNewMax ? mrAccent.opacity(0.07) : .clear)
            }

            Text("행 탭 → 실행 안내 · 연한 배경 = 새 최장 롱런 주 · 거리는 이지 페이스 기준")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text(l.note).font(.system(size: 12))
                            .foregroundStyle(l.isImpossible ? mrWarn : mrAccent)
                    }
                }

                // 병목이 어느 목표인지 짚어준다 — 이게 이 카드의 존재 이유다.
                if let bottleneck = bottleneckName {
                    Text("\(bottleneck) 목표를 조정하시면 나머지 둘과 맞아떨어집니다.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
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
            // ⚠ 3주 미만은 훈련으로 바꿀 수 있는 게 없다.
            //   억지로 계획을 만들면 지키지 못할 약속이 된다.
            Text("대회가 가까워 훈련 계획을 세우지 않습니다. 지금부터는 쌓기보다 아끼는 편이 낫습니다.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            if let p = prediction {
                Text("지금 상태로 \(mrFormatDisplay(p.midMin)) 정도입니다")
                    .font(.system(size: 14)).foregroundStyle(.white)
                    .padding(.top, 2)
                Text(String(format: "대회 날 기온을 %.0f°C로 봤습니다 (예년 이맘때 본인 러닝 기준)", raceTemp))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
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

    var body: some View {
        VStack(spacing: 14) {
            if case .ready = engine.state {
                if engine.raceItems.isEmpty && !engine.userInput.races.isEmpty {
                    Text("아직 예상 기록을 낼 만한 기록이 부족합니다.\n대회에 준하는 노력이 몇 번 쌓이면 여기에 나타납니다.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(28)
                }
                MRGoalLinksView(links: mrGoalLinks(engine.userInput.goals))
                ForEach(engine.raceItems) { item in
                    switch item {
                    case .planned(let c):
                        MRRacePlanCard(check: c)
                    case .planless(let r):
                        MRPlanlessRaceCard(race: r)
                    }
                }
            } else if case .loading = engine.state {
                ProgressView().tint(.white).frame(height: 80)
            }
        }
    }
}
