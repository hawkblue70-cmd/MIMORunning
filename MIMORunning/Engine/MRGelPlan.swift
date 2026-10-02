import Foundation

/// 대회 젤 보급 제안 — 예상 기록과 거리로 "언제(시간·km) 어떤 젤"을 정한다. 순수 로직.
/// 나 탭 대회 카드의 준비 비교 블록 바로 위에 붙는다.
///
/// 근거
/// · ACSM/AND/DC 2016: 1~2.5시간 30~60 g/h, 2.5시간 초과 최대 90 g/h(포도당:과당 혼합)
/// · 카페인 3~6 mg/kg, 섭취 후 30~60분 피크(Guest 2021 ISSN position stand)
/// · 간격 기준: 서브3 풀 "출발 전 + 7km(≈30분)마다, 21km 카페인", 하프 "출발 전 + 8~9km 카페인 1개"
///   (민재홍 영상 정리) — 거리는 페이스마다 달라지므로 **시간 간격**으로 환산해 쓴다.
///
/// ⚠ 젤 1개는 국내 흔한 제품 기준 탄수화물 22~25g(MRAdviceQueue와 같은 가정).
///   젤만으로 60~90 g/h를 채우려 간격을 좁히면 위장 문제가 늘어 — 간격은 유지하고 나머지는 음료로.
enum MRGelPlan {

    enum Kind: Equatable { case regular, caffeine }

    struct Stop: Equatable {
        /// 출발 후 경과 분
        let minute: Double
        /// 그 시점 예상 거리(km)
        let km: Double
        let kind: Kind
    }

    struct Plan: Equatable {
        let projectedMin: Double
        let distanceKm: Double
        let intervalMin: Double
        let stops: [Stop]
        /// 젤만으로 시간당 탄수화물(g) — 22~25g 가정
        let gelCarbsPerHourLo: Int
        let gelCarbsPerHourHi: Int
        /// ACSM 권장 구간(g/h)
        let recommendedLo: Int
        let recommendedHi: Int
    }

    static let gelCarbsLo = 22.0
    static let gelCarbsHi = 25.0
    /// 마지막 젤 뒤로 남아야 하는 최소 시간 — 이보다 짧으면 흡수돼 쓰이기 전에 끝난다
    static let minTailMin = 30.0

    static func build(distanceM: Double, projectedMin: Double) -> Plan? {
        guard distanceM >= 9500, projectedMin > 0 else { return nil }
        let km = distanceM / 1000
        // 10km 대(하프 미만)는 저장된 글리코겐으로 충분 — 출발 전 1개만
        if distanceM < 20000 {
            return Plan(projectedMin: projectedMin, distanceKm: km, intervalMin: 0, stops: [],
                        gelCarbsPerHourLo: 0, gelCarbsPerHourHi: 0, recommendedLo: 0, recommendedHi: 0)
        }
        guard projectedMin >= 75 else { return nil }
        let pace = projectedMin / km            // 분/km
        let long = projectedMin >= 150
        let interval: Double = long ? 30 : 40

        var minutes: [Double] = []
        var t = interval
        while projectedMin - t >= minTailMin {
            minutes.append(t)
            t += interval
        }
        guard !minutes.isEmpty else { return nil }

        // 카페인 — 피크(섭취 후 30~60분)가 지치는 구간에 오도록.
        // 풀(30km↑): 35km 지점(≈83%)보다 60분 앞. 서브3면 90분 = 21km.
        // 하프: 16km 지점(≈75%)보다 35분 앞. 1:45면 40분 ≈ 8km.
        let caffeineTarget = km >= 30 ? projectedMin * 0.83 - 60 : projectedMin * 0.75 - 35
        let caffeineIdx = minutes.indices.min { abs(minutes[$0] - caffeineTarget) < abs(minutes[$1] - caffeineTarget) } ?? 0

        let stops = minutes.enumerated().map { i, m in
            Stop(minute: m, km: m / pace, kind: i == caffeineIdx ? .caffeine : .regular)
        }
        let hours = projectedMin / 60
        let n = Double(stops.count)
        return Plan(projectedMin: projectedMin, distanceKm: km, intervalMin: interval, stops: stops,
                    gelCarbsPerHourLo: Int((n * gelCarbsLo / hours).rounded()),
                    gelCarbsPerHourHi: Int((n * gelCarbsHi / hours).rounded()),
                    recommendedLo: long ? 60 : 30,
                    recommendedHi: long ? 90 : 60)
    }

    // MARK: - 표시 문구

    /// 경과 시간 "0:40" · "1:30"
    static func elapsed(_ minute: Double) -> String {
        let m = Int(minute.rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    static func kmText(_ km: Double) -> String {
        "\(Int(km.rounded()))km"
    }

    static func title(_ p: Plan) -> String {
        AppLanguage.shared.s("젤 보급 제안 · 예상 \(mrFormatDisplay(p.projectedMin)) 기준",
                             "Gel plan · based on projected \(mrFormatDisplay(p.projectedMin))")
    }

    static func gelName(_ k: Kind) -> String {
        let L = AppLanguage.shared
        switch k {
        case .regular:  return L.s("일반 젤", "Gel")
        case .caffeine: return L.s("카페인 젤", "Caffeine gel")
        }
    }

    static func preStartLabel() -> String {
        AppLanguage.shared.s("출발 15~20분 전", "15–20 min before start")
    }

    static func summary(_ p: Plan) -> String {
        let L = AppLanguage.shared
        let iv = Int(p.intervalMin)
        if p.stops.isEmpty {
            return L.s("이 거리는 몸에 저장된 에너지로 충분합니다 — 레이스 중 보급은 필요 없습니다.",
                       "Your stored energy covers this distance — no fueling needed during the race.")
        }
        if p.recommendedLo >= 60 {
            return L.s("레이스 중 \(p.stops.count)개 · \(iv)분마다 · 젤만으로 시간당 약 \(p.gelCarbsPerHourLo)~\(p.gelCarbsPerHourHi)g — 권장 \(p.recommendedLo)~\(p.recommendedHi)g까지는 스포츠음료로 채우세요.",
                       "\(p.stops.count) during the race · every \(iv) min · gels alone give ~\(p.gelCarbsPerHourLo)–\(p.gelCarbsPerHourHi) g/h — top up toward \(p.recommendedLo)–\(p.recommendedHi) g/h with sports drink.")
        }
        return L.s("레이스 중 \(p.stops.count)개 · \(iv)분마다 · 시간당 약 \(p.gelCarbsPerHourLo)~\(p.gelCarbsPerHourHi)g(권장 \(p.recommendedLo)~\(p.recommendedHi)g).",
                   "\(p.stops.count) during the race · every \(iv) min · ~\(p.gelCarbsPerHourLo)–\(p.gelCarbsPerHourHi) g/h (guideline \(p.recommendedLo)–\(p.recommendedHi) g).")
    }

    static func caffeineNote() -> String {
        AppLanguage.shared.s("카페인은 체중 1kg당 3mg 안팎(70kg ≈ 200mg). 평소 커피에 예민하면 빼세요.",
                             "Caffeine ≈ 3 mg per kg body weight (70 kg ≈ 200 mg). Skip it if you're sensitive to coffee.")
    }

    static func disclaimer() -> String {
        AppLanguage.shared.s("참고용 제안입니다. 대회 전 롱런에서 같은 젤·같은 간격으로 반드시 연습해 보고, 몸에 맞게 조정하세요.",
                             "For reference only. Always rehearse the same gels at the same intervals on long runs before race day, and adjust to what your body tolerates.")
    }
}
