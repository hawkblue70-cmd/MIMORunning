import Foundation

// MARK: - 목표끼리 앞뒤가 맞는가
//
// 세 거리 목표를 각각 입력하면 그 사이에 **암묵적 지수**가 생긴다.
// 그게 사람이 가질 수 있는 범위 밖이면 셋 중 하나가 나머지와 모순이라는 뜻이다.
//
// ⚠ 밴드는 지어낸 값이 아니다:
//   · 10K→하프 1.05–1.10 — Vickers & Vertosick 2016이 **직접 검증**한 구간.
//     Riegel k=1.07이 10K(p=0.9)와 하프(p=0.3)에서 잘 교정되어 있었다.
//   · 하프→풀 1.05–1.30 — 준비 상태에 따라 크게 벌어진다. 좁게 잡으면 안 된다.
//   · 10K→풀 1.06–1.16 — 위 둘의 합성.
//
// ⚠ Blythe & Király 2016의 "중앙 1.12"는 여기 쓸 수 없다.
//   그건 100m부터 마라톤까지를 관통하는 단일 지수이고
//   표본도 영국 클럽 러너 상위 25%다.
//
// **판단이 아니라 어느 것이 병목인지 알려주기 위한 계산이다.**

struct MRGoalLink {
    let name: String
    let b: Double
    let lo: Double
    let hi: Double
    var inRange: Bool { b >= lo && b <= hi }
    // ⚠ b < 1.00 은 "긴 거리를 짧은 거리보다 빠른 페이스로 뛴다"는 뜻이라
    //   물리적으로 성립하지 않는다. "야심차다"로 뭉뚱그리면 안 된다.
    //   다만 사람이 아니라 **숫자에** 대고 말한다.
    var isImpossible: Bool { b < 1.00 }
    var note: String {
        if b < 1.00 { return "이 조합은 성립하지 않습니다" }
        if inRange  { return "서로 맞습니다" }
        return b < lo ? "장거리 목표가 상대적으로 더 야심찹니다"
                      : "단거리 목표가 상대적으로 더 야심찹니다"
    }
}

func mrGoalLinks(_ g: MRGoals) -> [MRGoalLink] {
    var out: [MRGoalLink] = []
    let t10 = g.minutes(for: MRDistance.d10)
    let th  = g.minutes(for: MRDistance.dH)
    let tf  = g.minutes(for: MRDistance.dF)

    if let a = t10, let b = th {
        out.append(MRGoalLink(name: "10K → 하프",
                              b: log(b / a) / log(MRDistance.dH / MRDistance.d10),
                              lo: 1.05, hi: 1.10))
    }
    if let a = th, let b = tf {
        out.append(MRGoalLink(name: "하프 → 풀",
                              b: log(b / a) / log(2.0), lo: 1.05, hi: 1.30))
    }
    if let a = t10, let b = tf {
        out.append(MRGoalLink(name: "10K → 풀",
                              b: log(b / a) / log(MRDistance.dF / MRDistance.d10),
                              lo: 1.06, hi: 1.16))
    }
    return out
}

// MARK: - 대회별: 계획대로 하면 목표에 닿는가

struct MRGoalCheck {
    let race: MRTargetRace
    let plan: MRRacePlan
    let goalMin: Double?
    let gapMin: Double?          // 양수 = 목표보다 느림
    let verdict: String
    let levers: [String]         // 무엇을 바꾸면 메워지는가
}

func mrCheckGoal(race: MRTargetRace,
                 plan: MRRacePlan,
                 goals: MRGoals,
                 profile: MRProfile,
                 halfEquivMin: Double,
                 heat: MRHeatModel,
                 raceTempC: Double) -> MRGoalCheck {

    guard let goal = goals.minutes(for: race.distanceM) else {
        return MRGoalCheck(race: race, plan: plan, goalMin: nil, gapMin: nil,
                           verdict: "", levers: [])
    }
    let gap = plan.projectedFinal - goal
    let pct = gap / goal * 100

    // ⚠ 판정이 아니라 거리감이다. "못 한다"고 쓰지 않는다.
    let verdict: String
    if gap <= 0 {
        verdict = "계획대로면 목표 안쪽입니다"
    } else if pct <= 3 {
        verdict = "사정권 — 당일 컨디션이 가르는 차이입니다"
    } else if pct <= 8 {
        verdict = "조금 모자랍니다. 아래를 바꾸면 메워집니다"
    } else {
        verdict = "이번 대회보다 다음 대회에 더 어울리는 목표입니다"
    }

    // ── 무엇을 바꾸면 메워지는가
    //
    // ⚠ 레버는 반드시 **계획후와 같은 조건**으로 계산해야 한다.
    //   v1은 계획후에는 피크 주간거리 + 테이퍼 + 기온 보정을 넣고
    //   레버에는 현재 주간거리만 넣었다. 그래서 "롱런을 25km로 늘리면
    //   4:27:54" — 계획후 4:25:25보다 **느린** 값이 나왔다.
    //   레버를 당겼는데 더 느려지는 화면은 신뢰를 통째로 무너뜨린다.
    //
    // ⚠ 어느 레버도 목표에 닿지 못하는데 레버를 늘어놓으면 조롱처럼 읽힌다.
    //   3시간을 목표로 한 사람에게 "롱런 28km → 4:15"를 보여주는 건
    //   닿지 않는 걸 닿을 것처럼 늘어놓는 것이다.
    //   → 20% 넘게 벌어지면 레버 대신 **목표가 요구하는 것**을 보여준다.
    let farOff = gap > 0 && pct > 20
    var levers: [String] = []
    if farOff && race.distanceM >= MRDistance.dF {
        // 지수를 이론상 최대(1.03)까지 끌어올려도 나오는 값
        // ⚠ projectedFinal과 같은 기온 조건이어야 한다
        var bestPossible = halfEquivMin * pow(2.0, 1.03) * (1 - MR_TAPER_GAIN)
        if heat.ok { bestPossible = heat.fromRef(timeRefMin: bestPossible, tempC: raceTempC) }
        let needHalf = goal / pow(2.0, 1.13)      // 준비된 아마추어 기준
        levers = [
            "이 목표는 하프를 \(mrFormatDisplay(needHalf))에 뛰는 몸을 전제합니다 (지금 \(mrFormatDisplay(halfEquivMin)))",
            "마라톤 준비를 최대로 끌어올려도 이번 대회는 \(mrFormatDisplay(bestPossible)) 부근이 한계선입니다",
        ]
    } else if farOff {
        let needHalf = goal / pow(race.distanceM / MRDistance.dH, 1.06)
        levers = ["이 목표는 하프 등가 \(mrFormatDisplay(needHalf))를 요구합니다 (지금 \(mrFormatDisplay(halfEquivMin)))"]
    } else if gap > 0 && race.distanceM >= MRDistance.dF {
        let volPeak = min(profile.weeklyKm4w * 1.35, 60.0)

        // 계획후와 동일하게: 테이퍼 이득 + 레이스 기온 환산
        func finish(_ b: Double) -> Double {
            var t = halfEquivMin * pow(2.0, b) * (1 - MR_TAPER_GAIN)
            if heat.ok { t = heat.fromRef(timeRefMin: t, tempC: raceTempC) }
            return t
        }

        // ⚠ 중복 제거. 롱런 페널티는 28km에서 끝나므로(Fokkema의 근거가
        //   거기까지다) 28km와 32km는 **같은 값이 나오는 게 정상**이다.
        //   그런데 나란히 보여주면 버그처럼 보인다. 같은 값은 하나만 남긴다.
        var seen = Set<Int>()
        func add(_ text: String, _ t: Double) {
            let key = Int(t.rounded())
            guard !seen.contains(key), t < plan.projectedFinal - 0.2 else { return }
            seen.insert(key)
            levers.append("\(text) → \(mrFormatDisplay(t))")
        }

        for lr in [25.0, 28.0, 32.0] where lr > plan.reachableLongKm {
            add("롱런 \(Int(lr))km",
                finish(bMarathonModel(weeklyKm: volPeak, longestKm: lr,
                                      finishes: profile.marathonFinishes).b))
        }
        for wk in [40.0, 50.0, 60.0] where wk > volPeak {
            add("주 \(Int(wk))km",
                finish(bMarathonModel(weeklyKm: wk, longestKm: plan.targetLongKm,
                                      finishes: profile.marathonFinishes).b))
        }
    } else if gap > 0 && pct > 3 {
        // ⚠ 사정권(3% 이내)에는 레버를 붙이지 않는다.
        //   0.4% 차이에 "이것도 하세요"를 붙이면 잔소리가 된다.
        //   하프 이하는 durability가 아니라 기본 속도 문제다.
        let needHalf = goal / pow(race.distanceM / MRDistance.dH, 1.06)
        levers.append(String(format: "이 목표는 하프 등가 %@를 요구합니다 (지금 %@, %+.1f%%)",
                             mrFormatDisplay(needHalf), mrFormatDisplay(halfEquivMin),
                             (halfEquivMin - needHalf) / needHalf * 100))
    }

    return MRGoalCheck(race: race, plan: plan, goalMin: goal,
                       gapMin: gap, verdict: verdict, levers: levers)
}
