import Foundation

enum MRDistance {
    static let d5  = 5000.0
    static let d10 = 10000.0
    static let dH  = 21097.5
    static let dF  = 42195.0
}

// v는 m/min, t는 분
func vo2Cost(_ v: Double) -> Double {
    -4.60 + 0.182258 * v + 0.000104 * v * v
}

func pctMax(_ t: Double) -> Double {
    0.8 + 0.1894393 * exp(-0.012778 * t) + 0.2989558 * exp(-0.1932605 * t)
}

func vdot(distanceM: Double, timeMin: Double) -> Double {
    vo2Cost(distanceM / timeMin) / pctMax(timeMin)
}

func paceForVDOT(_ v: Double, _ f: Double) -> Double {
    let a = 0.000104, b = 0.182258, c = -4.60 - f * v
    let speed = (-b + sqrt(b * b - 4 * a * c)) / (2 * a)
    return 60_000.0 / speed
}

// MARK: - 마라톤 지수
//
// 하프 기록에서 풀 기록을 얻는 지수. T_full = T_half × 2^b
// 세 계수 전부 발표된 논문 값이고, 특정 사용자에게 맞춘 것은 하나도 없다.

/// 반환: (지수, 추가 불확실도 SD)
func bMarathonModel(weeklyKm: Double,
                    longestKm: Double,
                    finishes: Int) -> (b: Double, extraSD: Double) {

    // ① 기준 1.13 — Vickers & Vertosick 2016
    //    (BMC Sports Sci Med Rehabil 8:26, n=2,303)
    //    ⚠ 논문이 보고한 값이 아니라 "Riegel 1.07 예측이 러너 절반에게
    //      10분 이상 빠르다"에서 역산한 값이다.
    //    ⚠ 같은 논문에서 10K와 하프는 1.07이 잘 교정되어 있다(p=0.9, p=0.3).
    //      하프 이하 지수는 절대 올리지 말 것.
    var b = 1.13

    // ② 롱런 — Fokkema 2020 (Scand J Med Sci Sports 30(9):1692–1704)
    //    ⚠ n은 997이 아니라 마라톤군 441.
    //    ⚠ 논문이 유의하게 보고한 것은 "<25km = +13.4분" 하나뿐이고,
    //      "30–35km가 최적"이라는 계수는 논문에 없다.
    //    ⚠ 범주 대비이지 연속 기울기가 아니다 → 부드러운 계단으로 구현.
    if longestKm <= 22.0 {
        b += 0.080
    } else if longestKm < 28.0 {
        b += 0.080 * (28.0 - longestKm) / 6.0
    }

    // ③ 볼륨 — Tanda 2011 (J Hum Sport Exerc 6(3):511–520)
    //    ⚠ n=22, 적합 범위는 주 40.4–110.7km뿐이다.
    //      exp(-0.0053K)는 저마일리지에서 기울기가 가장 가파른데
    //      거기가 바로 외삽 구간이라 clamp한다.
    let k = min(max(weeklyKm, 30.0), 110.0)
    b += 0.22 * (exp(-0.0053 * k) - exp(-0.0053 * 45.0))

    // ④ 완주 경험
    if finishes == 0 {
        b += 0.02
    } else if finishes >= 2 {
        b -= 0.02
    }

    // ⑤ 나이 항 없음 — Vickers 2016에서 거리×나이 상호작용의 증거가 없다.
    //    ⚠ WMA 연령 계수로 역산하지 말 것. 그건 세계기록 tail 모집단이다.
    b = min(max(b, 1.03), 1.32)

    // ⑥ 적합 범위 밖이면 불확실도를 키운다
    var extra = 0.0
    if weeklyKm < 40.0 {
        extra += 0.02 * min((40.0 - weeklyKm) / 20.0, 1.0)
    }
    if longestKm > 22.0 && longestKm < 32.0 {
        extra += 0.020        // 이 구간은 논문에 데이터가 없다
    }
    return (b, extra)
}

// MARK: - 실측 지수의 베이즈 축소

let bPopMean = 1.15       // 인구 사전확률 (Vickers 역산 기반)
let bPopSD   = 0.06
let bRaceDaySD = 0.05     // 단일 레이스의 당일 변동

/// 한 번의 나쁜 레이스를 그 사람의 '체질'로 굳히지 않기 위해서다.
func shrinkMeasuredB(_ bObs: Double, nObs: Int = 1) -> (post: Double, sd: Double) {
    let s2 = (bRaceDaySD * bRaceDaySD) / Double(max(nObs, 1))
    let t2 = bPopSD * bPopSD
    let post = (bObs / s2 + bPopMean / t2) / (1 / s2 + 1 / t2)
    return (post, sqrt(1 / (1 / s2 + 1 / t2)))
}
