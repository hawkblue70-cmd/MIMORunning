import Foundation

/// 강도 허용 공용 판정(2026-10-20) — 아침 제안과 러닝 뒤 총평이 **같은 조건**으로 "강도 넣기"를 막는다.
/// 예전엔 두 엔진이 따로 판단해, 아침은 "손목 온도 높음 → 이지런"인데 러닝 뒤 총평은 "충분히 회복 · 템포런 넣기 좋은 시점"이 나왔다.
/// 막는 조건: 밤 활력 징후 이상(손목 온도·호흡수) · HRV 아래 · HRV 불안정 · 어젯밤 HRV 평소보다 15%↑ 낮음.
/// 진단하지 않는다 — 사실만 말한다.
enum MRIntensityGate {
    enum Reason: Equatable {
        case vital(MRVitalSignal)
        case shortSleep(hours: Double)
        case hrvBelow
        case hrvVolatile
        case lastNightHRVLow
    }

    /// 어젯밤 잠든 시간이 이보다 짧으면 강도를 막는다 — 임의로 정함. 수면 제한 연구는 6시간 미만부터 수행 저하를 보고한다
    /// (Fullagar 2015 리뷰 등). HRV가 평소 범위여도 3시간 14분 잔 날 "강도 OK"가 나왔다(2026-10-27).
    static let shortSleepHours = 5.0

    /// 강도를 막아야 하면 그 이유(우선순위: 활력 징후 > 짧은 수면 > HRV 아래 > 불안정 > 어젯밤 낮음). 열려 있으면 nil.
    static func closedReason(vital: MRVitalSignal?, hrvTrend: MRHRVTrend?, lastNightHRV: Double?,
                             lastNightSleepHours: Double? = nil) -> Reason? {
        if let v = vital { return .vital(v) }
        if let h = lastNightSleepHours, h > 0, h < shortSleepHours { return .shortSleep(hours: h) }
        if let t = hrvTrend {
            if t.state == .below { return .hrvBelow }
            if t.isVolatile { return .hrvVolatile }
            if let n = lastNightHRV, MRReadiness.lastNightDeviation(n, trend: t) < 0 { return .lastNightHRVLow }
        }
        return nil
    }

    /// 사실 문장 — "어젯밤 손목 온도가 평소보다 1.1°C 높았습니다." / "HRV가 기준선 아래입니다." …
    static func fact(_ r: Reason) -> String {
        let L = AppLanguage.shared
        switch r {
        case .vital(let v): return v.postRunCause
        case .shortSleep(let h): return L.s("어젯밤 수면이 \(sleepText(h))이었습니다.", "You slept \(sleepText(h)) last night.", ja: "昨夜の睡眠は\(sleepText(h))でした。")
        case .hrvBelow: return L.s("HRV가 기준선 아래입니다.", "HRV is below baseline.", ja: "HRVが基準線を下回っています。")
        case .hrvVolatile: return L.s("이번 주 HRV가 크게 흔들립니다.", "HRV is swinging a lot this week.", ja: "今週はHRVが大きく揺れています。")
        case .lastNightHRVLow: return L.s("어젯밤 HRV가 평소보다 낮았습니다.", "Last night's HRV was below usual.", ja: "昨夜のHRVが普段より低かったです。")
        }
    }

    /// 아침 제안 태그 — 판정 줄 뒤에 붙는 짧은 근거
    static func tag(_ r: Reason) -> String {
        let L = AppLanguage.shared
        switch r {
        case .vital(let v): return v.tag
        case .shortSleep(let h): return L.s("어젯밤 수면 \(sleepText(h))", "slept \(sleepText(h))", ja: "昨夜の睡眠\(sleepText(h))")
        case .hrvBelow: return L.s("HRV 기준선 아래", "HRV below baseline", ja: "HRVが基準線未満")
        case .hrvVolatile: return L.s("HRV 흔들림", "HRV swinging", ja: "HRVの揺れ")
        case .lastNightHRVLow: return L.s("어젯밤 HRV 낮음", "low HRV last night", ja: "昨夜のHRVが低い")
        }
    }

    /// "3시간 14분" / "3h 14m" / "3時間14分"
    static func sleepText(_ hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        let h = total / 60, m = total % 60
        return AppLanguage.shared.s("\(h)시간 \(m)분", "\(h)h \(m)m", ja: "\(h)時間\(m)分")
    }
}
