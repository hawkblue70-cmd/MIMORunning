import Foundation

/// 강도 허용 공용 판정(2026-10-20) — 아침 제안과 러닝 뒤 총평이 **같은 조건**으로 "강도 넣기"를 막는다.
/// 예전엔 두 엔진이 따로 판단해, 아침은 "손목 온도 높음 → 이지런"인데 러닝 뒤 총평은 "충분히 회복 · 템포런 넣기 좋은 시점"이 나왔다.
/// 막는 조건: 밤 활력 징후 이상(손목 온도·호흡수) · HRV 아래 · HRV 불안정 · 어젯밤 HRV 평소보다 15%↑ 낮음.
/// 진단하지 않는다 — 사실만 말한다.
enum MRIntensityGate {
    enum Reason: Equatable {
        case vital(MRVitalSignal)
        case hrvBelow
        case hrvVolatile
        case lastNightHRVLow
    }

    /// 강도를 막아야 하면 그 이유(우선순위: 활력 징후 > HRV 아래 > 불안정 > 어젯밤 낮음). 열려 있으면 nil.
    static func closedReason(vital: MRVitalSignal?, hrvTrend: MRHRVTrend?, lastNightHRV: Double?) -> Reason? {
        if let v = vital { return .vital(v) }
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
        case .hrvBelow: return L.s("HRV 기준선 아래", "HRV below baseline", ja: "HRVが基準線未満")
        case .hrvVolatile: return L.s("HRV 흔들림", "HRV swinging", ja: "HRVの揺れ")
        case .lastNightHRVLow: return L.s("어젯밤 HRV 낮음", "low HRV last night", ja: "昨夜のHRVが低い")
        }
    }
}
