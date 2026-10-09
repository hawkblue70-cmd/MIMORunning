import Foundation

// MARK: - 밤 활력 징후 — 호흡수 · 손목 온도 (2026-10-09)
//
// 애플 활력 징후 앱의 다섯 지표 중 두 개만 아침 제안 재료로 쓴다. 화면(차트)은 없다 — 평소 범위 안이면 아무 말도 안 하고,
// 벗어난 날에만 아침 제안 판정·둘째 줄이 바뀐다(사용자 결정: "차트는 넣지 말고 이상 징후만").
//   · 호흡수·손목 온도는 감기·몸살 같은 컨디션 이상을 HRV보다 먼저, 또렷하게 보이는 경우가 많다
//     (Natarajan 2020 · Mishra 2020: 증상 전후 수면 호흡수 상승, 손목 온도 상승).
//   · 혈중 산소는 뺐다 — 워치 값은 밤마다 흔들림이 커 잘못 울릴 위험이 크다. 수면 심박은 안정시 심박 규칙이 맡는다.
//   · 의료 판단이 아니다 — 문구는 사실(값·평소)과 "몸 상태를 먼저 확인하세요"까지만.
//
// 기준은 본인 4주(어젯밤 전 28일) 중앙값. 한 밤만 벗어나면 이지런(손목 온도 하나는 술·더운 방으로도 오른다),
// 둘 다 벗어나거나 하나가 2밤 연속이면 휴식. 워치를 차고 자지 않았거나(SE는 온도 없음) 4주 14밤 미만이면 조용히 빠진다.

/// 호흡수 — 어젯밤이 평소(4주 중앙값)보다 이만큼(회/분) 이상 높으면 벗어남. 임시값 — 실기기 1년 로그로 확정한다.
let MR_VITAL_RESP_RISE: Double = 1.5
/// 손목 온도 — 평소보다 이만큼(°C) 이상 높으면 벗어남. 임시값 — 실기기 1년 로그로 확정한다.
let MR_VITAL_TEMP_RISE: Double = 0.5
/// 평소 범위를 잡는 최소 밤 수(28일 중)
let MR_VITAL_MIN_BASELINE_NIGHTS = 14

struct MRVitalElevation: Equatable {
    enum Kind: Equatable { case respiratory, wristTemp }
    let kind: Kind
    /// 어젯밤 포함 연속으로 벗어난 밤 수
    let nights: Int
    let latest: Double
    let usual: Double
    var rise: Double { latest - usual }
}

/// 손목 온도 밤 값 — 샘플은 한 밤에 하나(수면 구간 전체)라 **끝 시각**(기상)으로 밤 키를 잡는다.
/// 15시 이후에 끝난 샘플(낮잠 등)은 다음 날 키. 같은 밤에 여럿이면 중앙값. 날짜(자정) 오름차순.
func mrWristTempNights(samples: [(end: Date, value: Double)],
                       calendar: Calendar = .current) -> [(date: Date, value: Double)] {
    var buckets: [Date: [Double]] = [:]
    for s in samples {
        let day = calendar.startOfDay(for: s.end)
        let key = calendar.component(.hour, from: s.end) >= 15
            ? (calendar.date(byAdding: .day, value: 1, to: day) ?? day) : day
        buckets[key, default: []].append(s.value)
    }
    return buckets.keys.sorted().map { ($0, mrMedian(buckets[$0]!)) }
}

/// 어젯밤(오늘 키) 값이 평소 + `rise` 이상이면 그 벗어남. 오늘 키 밤이 없으면(안 차고 잠·동기화 전) nil —
/// 며칠 전 값으로 오늘을 말하지 않는다. 연속 밤 수는 하루씩 거슬러 각 밤의 그 전 28일 중앙값과 비교한다.
func mrVitalElevation(nights: [(date: Date, value: Double)], kind: MRVitalElevation.Kind,
                      rise: Double, asOf: Date,
                      calendar cal: Calendar = .current) -> MRVitalElevation? {
    var byDay: [Date: Double] = [:]
    for n in nights { byDay[cal.startOfDay(for: n.date)] = n.value }
    let today = cal.startOfDay(for: asOf)
    guard let last = byDay[today] else { return nil }

    func usual(before day: Date) -> Double? {
        let lo = cal.date(byAdding: .day, value: -28, to: day)!
        let vals = byDay.filter { $0.key >= lo && $0.key < day }.map(\.value)
        return vals.count >= MR_VITAL_MIN_BASELINE_NIGHTS ? mrMedian(vals) : nil
    }

    guard let lastUsual = usual(before: today), last >= lastUsual + rise else { return nil }
    var count = 1
    var d = cal.date(byAdding: .day, value: -1, to: today)!
    while let v = byDay[d], let u = usual(before: d), v >= u + rise {
        count += 1
        d = cal.date(byAdding: .day, value: -1, to: d)!
    }
    return MRVitalElevation(kind: kind, nights: count, latest: last, usual: lastUsual)
}

/// 아침 제안이 쓰는 묶음 — 벗어난 것만 담는다. 비어 있으면 규칙이 빠진다.
struct MRVitalSignal: Equatable {
    let elevations: [MRVitalElevation]

    /// 둘 다 벗어났거나 하나가 2밤 연속 → 휴식. 하나·한 밤 → 이지런.
    var isRest: Bool { elevations.count >= 2 || elevations.contains { $0.nights >= 2 } }

    /// 근거 조각 — "어젯밤 호흡수 16.8회(평소 14.5)" · "손목 온도 평소보다 +0.6°C". 연속이면 "N밤째".
    var pieces: [String] {
        let L = AppLanguage.shared
        return elevations.map { e in
            switch e.kind {
            case .respiratory:
                let v = String(format: "%.1f", e.latest), u = String(format: "%.1f", e.usual)
                return e.nights >= 2
                    ? L.s("호흡수 \(e.nights)밤째 \(v)회(평소 \(u))", "respiratory rate \(e.nights) nights: \(v)/min (usual \(u))", ja: "呼吸数 \(e.nights)晩目 \(v)回(普段 \(u))")
                    : L.s("어젯밤 호흡수 \(v)회(평소 \(u))", "last night's respiratory rate \(v)/min (usual \(u))", ja: "昨夜の呼吸数 \(v)回(普段 \(u))")
            case .wristTemp:
                let r = String(format: "+%.1f", e.rise)
                return e.nights >= 2
                    ? L.s("손목 온도 \(e.nights)밤째 평소보다 \(r)°C", "wrist temp \(r)°C above usual for \(e.nights) nights", ja: "手首温度 \(e.nights)晩続けて普段より\(r)°C")
                    : L.s("손목 온도 평소보다 \(r)°C", "wrist temp \(r)°C above usual", ja: "手首温度 普段より\(r)°C")
            }
        }
    }

    /// 판정 줄 태그 — "호흡수·손목 온도 높음"
    var tag: String {
        let L = AppLanguage.shared
        let names = elevations.map { e -> String in
            switch e.kind {
            case .respiratory: return L.s("호흡수", "respiratory rate", ja: "呼吸数")
            case .wristTemp:   return L.s("손목 온도", "wrist temp", ja: "手首温度")
            }
        }
        return L.s("\(names.joined(separator: "·")) 높음", "\(names.joined(separator: " & ")) up", ja: "\(names.joined(separator: "・"))が高い")
    }

    /// "왜" 문장 — 진단하지 않는다. 사실 → 오늘 할 일 → 몸 상태 확인.
    var why: String {
        let L = AppLanguage.shared
        let check = L.s("몸 상태를 먼저 확인하세요.", "Check how your body feels first.", ja: "まず体調を確かめてください。")
        if elevations.count >= 2 {
            return L.s("어젯밤 호흡수와 손목 온도가 모두 평소보다 높습니다. 오늘은 쉬거나 30분 이내로 가볍게 가세요. ",
                       "Both respiratory rate and wrist temperature were above usual last night. Rest, or keep it under 30 minutes and easy. ",
                       ja: "昨夜は呼吸数と手首温度がどちらも普段より高めでした。今日は休むか、30分以内で軽くしてください。") + check
        }
        guard let e = elevations.first else { return "" }
        let name: String = {
            switch e.kind {
            case .respiratory: return L.s("호흡수가", "respiratory rate has", ja: "呼吸数が")
            case .wristTemp:   return L.s("손목 온도가", "wrist temperature has", ja: "手首温度が")
            }
        }()
        if e.nights >= 2 {
            return L.s("\(name) \(e.nights)밤째 평소보다 높습니다. 오늘은 쉬거나 30분 이내로 가볍게 가세요. ",
                       "Your \(name) been above usual for \(e.nights) nights. Rest, or keep it under 30 minutes and easy. ",
                       ja: "\(name)\(e.nights)晩続けて普段より高めです。今日は休むか、30分以内で軽くしてください。") + check
        }
        let nameNow: String = {
            switch e.kind {
            case .respiratory: return L.s("호흡수가", "respiratory rate was", ja: "呼吸数が")
            case .wristTemp:   return L.s("손목 온도가", "wrist temperature was", ja: "手首温度が")
            }
        }()
        return L.s("어젯밤 \(nameNow) 평소보다 높습니다. 하룻밤이지만 오늘은 강도를 빼고 이지런으로 가세요. ",
                   "Last night your \(nameNow) above usual. One night, but skip the intensity today and keep it easy. ",
                   ja: "昨夜は\(nameNow)普段より高めでした。一晩だけですが、今日は強度を抜いてイージーランにしてください。") + check
    }
}

/// 두 지표를 한 번에 판정. 벗어난 게 없으면 nil.
func mrVitalSignal(respNights: [(date: Date, value: Double)],
                   tempNights: [(date: Date, value: Double)],
                   asOf: Date, calendar: Calendar = .current) -> MRVitalSignal? {
    let e = [
        mrVitalElevation(nights: respNights, kind: .respiratory, rise: MR_VITAL_RESP_RISE, asOf: asOf, calendar: calendar),
        mrVitalElevation(nights: tempNights, kind: .wristTemp, rise: MR_VITAL_TEMP_RISE, asOf: asOf, calendar: calendar),
    ].compactMap { $0 }
    return e.isEmpty ? nil : MRVitalSignal(elevations: e)
}

#if DEBUG
/// 임계값 후보별로 지난 1년 동안 몇 밤 울렸을지 — 실기기 로그로 임계값을 정한다(안정시 심박 규칙과 같은 방식).
/// 각 후보마다 "하나만 한 밤(이지)" · "휴식(둘 다 또는 2밤 연속)" 밤 수를 센다.
func mrVitalThresholdReport(respNights: [(date: Date, value: Double)],
                            tempNights: [(date: Date, value: Double)],
                            asOf: Date, days: Int = 365,
                            calendar cal: Calendar = .current) -> [String] {
    let today = cal.startOfDay(for: asOf)
    var out: [String] = []
    for (rr, tt) in [(1.0, 0.4), (1.5, 0.5), (2.0, 0.7)] {
        var easy = 0, rest = 0, respOnly = 0, tempOnly = 0, evaluated = 0
        for back in 0..<days {
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            let r = mrVitalElevation(nights: respNights, kind: .respiratory, rise: rr, asOf: day, calendar: cal)
            let t = mrVitalElevation(nights: tempNights, kind: .wristTemp, rise: tt, asOf: day, calendar: cal)
            if respNights.contains(where: { cal.isDate($0.date, inSameDayAs: day) })
                || tempNights.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) { evaluated += 1 }
            let e = [r, t].compactMap { $0 }
            guard !e.isEmpty else { continue }
            if r != nil && t == nil { respOnly += 1 }
            if t != nil && r == nil { tempOnly += 1 }
            if MRVitalSignal(elevations: e).isRest { rest += 1 } else { easy += 1 }
        }
        out.append(String(format: "호흡 +%.1f · 온도 +%.1f → 이지 %d밤 · 휴식 %d밤 (호흡만 %d · 온도만 %d) / 자료 있는 밤 %d",
                          rr, tt, easy, rest, respOnly, tempOnly, evaluated))
    }
    return out
}
#endif
