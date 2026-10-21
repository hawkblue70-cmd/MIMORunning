import Foundation

/// 심박 시계열 평활화 — 리듬 카드 심박 차트와 총평(`RunSummaryBuilder`)의 "최고 N"이 **같은 값**을 보게
/// 이 파일 하나만 쓴다.

func hrMovingMedian(_ data: [Int], window: Int) -> [Double] {
    guard !data.isEmpty else { return [] }
    return data.indices.map { i in
        let lo = max(0, i - window / 2)
        let hi = min(data.count - 1, i + window / 2)
        let slice = data[lo...hi].sorted()
        let m = slice.count / 2
        return slice.count % 2 == 0 && slice.count > 1
            ? Double(slice[m - 1] + slice[m]) / 2
            : Double(slice[m])
    }
}

func hrMovingAverage(_ data: [Double], window: Int) -> [Double] {
    guard !data.isEmpty else { return [] }
    return data.indices.map { i in
        let lo = max(0, i - window / 2)
        let hi = min(data.count - 1, i + window / 2)
        let slice = data[lo...hi]
        return slice.reduce(0, +) / Double(slice.count)
    }
}

/// 심박 타임라인 차트와 같은 2단 평활화(이동 중앙값 9 → 이동 평균 25).
/// 차트 축 라벨과 총평 근거의 "최고 N"이 **같은 값**을 보게 이 함수 하나만 쓴다.
func hrChartSmoothed(_ bpm: [Int]) -> [Double] {
    hrMovingAverage(hrMovingMedian(bpm, window: 9), window: 25)
}

/// 출발 직후 광학 심박 오독 구간의 표본 수(첫 10% + 그 뒤 떨어지기 전 튐 꼬리, nil = 없음).
/// 규칙: 첫 10%(60초~10분) 평균이 그 다음 10~40% 구간 평균보다 15bpm 이상 높고, 그 뒤로는 초반 평균 −5 위로
/// 다시 올라오지 않으면 초반 구간을 오독으로 본다. 생리적으로 출발 직후 심박은 낮게 시작해 올라가므로,
/// 출발이 가장 높고 곧 급락한 뒤 회복이 없는 모양은 측정 문제일 가능성이 크다(10분 미만 러닝은 판단하지 않음).
/// 존 비율·차트는 건드리지 않고, 전후반 비교·최고치 같은 **판정**에서만 제외한다.
func hrEarlyArtifactCount(_ samples: [(offset: TimeInterval, bpm: Int)]) -> Int? {
    guard samples.count >= 30, let first = samples.first, let last = samples.last else { return nil }
    let total = last.offset - first.offset
    guard total >= 600 else { return nil }
    let cut = first.offset + min(600, max(60, total * 0.10))
    let refEnd = first.offset + total * 0.40
    let early = samples.filter { $0.offset < cut }
    let ref = samples.filter { $0.offset >= cut && $0.offset < refEnd }
    guard early.count >= 10, ref.count >= 10 else { return nil }
    let earlyAvg = Double(early.map(\.bpm).reduce(0, +)) / Double(early.count)
    let refAvg = Double(ref.map(\.bpm).reduce(0, +)) / Double(ref.count)
    guard earlyAvg - refAvg >= 15 else { return nil }
    // "다시 올라오는가"는 튐이 끝난 뒤(초반 평균 −5 아래로 처음 떨어진 표본)부터 본다 — 튐이 첫 10%보다 길면
    // 그 꼬리가 '다시 올라온 것'으로 잡혀 오독을 놓쳤다(48분 러닝 · 첫 5분 튐). 제외 표본도 튐 꼬리까지.
    let later = samples.filter { $0.offset >= cut }
    guard let drop = later.firstIndex(where: { Double($0.bpm) < earlyAvg - 5 }) else { return nil }
    let laterMax = later[drop...].map(\.bpm).max() ?? 0
    guard Double(laterMax) < earlyAvg - 5 else { return nil }
    return early.count + drop
}

// MARK: - 초반 km 광학 심박 오독 (km 단위)

/// 초반 몇 km가 **더 느린데 심박은 더 높았다가** 빨라지는 순간 뚝 떨어지고, 그 뒤로 다시 그 높이에 오르지 않으면
/// 그 km들을 오독으로 본다(앞에서 몇 km인지, nil = 없음). `hrEarlyArtifactCount`(첫 10%가 가장 높은 모양)와
/// 중간 튐(7분 이하·갑자기)이 놓친 모양 — 8°C 저녁, 6'45"·6'40"·6'33"에 151·159·164였다가 6'06"에 141(2026-10-21).
/// 몸은 27초/km 빨라지며 심박이 23bpm 떨어지지 않는다.
/// 규칙(모두): 풀 km 6개↑ · 경계 k는 앞 1/3 이내 · km k → k+1에서 15초/km↑ 빨라지며 심박 15bpm↑ 떨어짐 ·
/// k+1 이후 최고 심박 < 앞 k km 최고 − 5 · 경계 앞뒤 km에 10m↑ 오르막/내리막이 없을 것(오르막 뒤 내리막은 실제 변화).
/// 존·차트는 그대로 두고 판정(디커플링·전후반 비교·같은 페이스 비교)에서만 뺀다 — 출발 직후 오독과 같은 원칙.
let hrEarlySplitDropBpm = 15
let hrEarlySplitFasterSec = 15.0
func hrEarlySplitArtifactKm(_ splits: [SplitData],
                            altitudeProfile: [(distanceKm: Double, altitude: Double)] = []) -> Int? {
    let full = splits.filter { $0.distanceM >= 900 && $0.avgHeartRate != nil }.sorted { $0.id < $1.id }
    guard full.count >= 6 else { return nil }
    func alt(at km: Double) -> Double? {
        guard !altitudeProfile.isEmpty else { return nil }
        return altitudeProfile.min { abs($0.distanceKm - km) < abs($1.distanceKm - km) }?.altitude
    }
    for k in stride(from: full.count / 3, through: 1, by: -1) {
        let a = full[k - 1], b = full[k]
        guard let ha = a.avgHeartRate, let hb = b.avgHeartRate,
              ha - hb >= hrEarlySplitDropBpm, a.paceSecPerKm - b.paceSecPerKm >= hrEarlySplitFasterSec else { continue }
        let leadMax = full[..<k].compactMap(\.avgHeartRate).max() ?? 0
        let restMax = full[k...].compactMap(\.avgHeartRate).max() ?? 0
        guard restMax < leadMax - 5 else { continue }
        // 경계 앞 km 오르막·뒤 km 내리막이면 지형 — 오독이 아니다
        if let a0 = alt(at: Double(k - 1)), let a1 = alt(at: Double(k)), let a2 = alt(at: Double(k + 1)),
           a1 - a0 >= 10 || a1 - a2 >= 10 { continue }
        return k
    }
    return nil
}

/// 초반 km 오독을 뺀 구간 목록 — 없으면 그대로.
func splitsExcludingEarlyHRArtifact(_ splits: [SplitData],
                                    altitudeProfile: [(distanceKm: Double, altitude: Double)] = []) -> [SplitData] {
    guard let k = hrEarlySplitArtifactKm(splits, altitudeProfile: altitudeProfile) else { return splits }
    let full = splits.filter { $0.distanceM >= 900 && $0.avgHeartRate != nil }.sorted { $0.id < $1.id }
    let lastBad = full[k - 1].id
    return splits.filter { $0.id > lastBad }
}

/// 초반 km 오독 구간의 끝 시각(러닝 시작부터 초) — 심박 표본에서 이 앞을 뺀다.
func hrEarlySplitArtifactEndOffset(_ splits: [SplitData],
                                   altitudeProfile: [(distanceKm: Double, altitude: Double)] = []) -> TimeInterval? {
    guard let k = hrEarlySplitArtifactKm(splits, altitudeProfile: altitudeProfile) else { return nil }
    let full = splits.filter { $0.distanceM >= 900 && $0.avgHeartRate != nil }.sorted { $0.id < $1.id }
    let lastBad = full[k - 1].id
    return splits.filter { $0.id <= lastBad }.reduce(0) { $0 + $1.duration }
}

// MARK: - 러닝 중간 광학 심박 튐

/// 러닝 중간에 심박만 갑자기 튄 구간을 찾아 그 구간 값을 주변 중앙값으로 바꾼 시계열.
/// 판정(존 분포·"최고 강도"·전후반 비교)에만 쓰고 차트는 원본 그대로 그린다 — 출발 직후 튐(`hrEarlyArtifactCount`)과 같은 원칙.
///
/// 튐으로 보는 구간(셋 다):
/// 1) 앞뒤 5분(±300초) 중앙값보다 15bpm 이상 높은 연속 구간, 길이 7분 이하, 그 안 최대 초과 20bpm 이상
/// 2) **갑자기 시작** — 구간 시작 30초 전에는 중앙값보다 5bpm 이하였다. 오르막·스퍼트의 심박은 1~2분에 걸쳐 오르므로
///    30초 전에 이미 절반쯤 올라와 있다. 광학 센서가 케이던스에 걸리거나 밀착이 풀리면 한두 표본 만에 뛴다.
/// 3) 러닝 전체에 1~2개뿐 — 3개 이상이면 반복 패턴(센서 불량이 계속되는 날 등)이라 한두 구간만 고치지 않는다.
///    15bpm↑ 구간 자체가 6개를 넘으면(인터벌·파틀렉) 아예 보지 않는다. 인터벌 회차는 1분 안팎에 걸쳐 올라 2)에서 대개 걸러진다.
/// 10분 미만 러닝은 판단하지 않는다.
func hrMidRunSpikeCleaned(_ samples: [(offset: TimeInterval, bpm: Int)]) -> [(offset: TimeInterval, bpm: Int)] {
    let ranges = hrMidRunSpikeRanges(samples)
    guard !ranges.isEmpty else { return samples }
    let sorted = samples.sorted { $0.offset < $1.offset }
    let med = hrRollingMedian(sorted, halfWindow: 300)
    return sorted.enumerated().map { i, s in
        ranges.contains(where: { $0.contains(i) }) ? (offset: s.offset, bpm: Int(med[i].rounded())) : s
    }
}

/// 러닝 중간 튐이 있는가 — 저장된 존을 다시 계산할지 정할 때 쓴다.
func hasHRMidRunSpike(_ samples: [(offset: TimeInterval, bpm: Int)]) -> Bool {
    !hrMidRunSpikeRanges(samples).isEmpty
}

/// 튐 구간(정렬된 표본의 인덱스 범위). 규칙은 `hrMidRunSpikeCleaned` 주석.
func hrMidRunSpikeRanges(_ samples: [(offset: TimeInterval, bpm: Int)]) -> [ClosedRange<Int>] {
    let s = samples.sorted { $0.offset < $1.offset }
    guard s.count >= 30, let first = s.first, let last = s.last, last.offset - first.offset >= 600 else { return [] }
    let med = hrRollingMedian(s, halfWindow: 300)
    let excess = s.indices.map { Double(s[$0].bpm) - med[$0] }
    var groups: [ClosedRange<Int>] = []
    var i = 0
    while i < s.count {
        guard excess[i] >= 15 else { i += 1; continue }
        var j = i
        while j + 1 < s.count && excess[j + 1] >= 15 { j += 1 }
        groups.append(i...j)
        i = j + 1
    }
    let spikes = groups.filter { g in
        let dur = s[g.upperBound].offset - s[g.lowerBound].offset
        guard dur <= 420, (g.map { excess[$0] }.max() ?? 0) >= 20 else { return false }
        // 갑자기 시작했나 — 시작 30초 전(그 사이 가장 가까운 표본)의 초과량
        let t0 = s[g.lowerBound].offset - 30
        guard let before = s[..<g.lowerBound].last(where: { $0.offset <= t0 }),
              let bi = s.firstIndex(where: { $0.offset == before.offset }) else { return false }
        return excess[bi] <= 5
    }
    guard !spikes.isEmpty, spikes.count <= 2, groups.count <= 6 else { return [] }
    return spikes
}

/// 시간(초) 기준 앞뒤 `halfWindow` 안 표본의 중앙값. `s`는 시간순 정렬돼 있어야 한다.
private func hrRollingMedian(_ s: [(offset: TimeInterval, bpm: Int)], halfWindow: TimeInterval) -> [Double] {
    var lo = 0, hi = 0
    return s.indices.map { i in
        while s[lo].offset < s[i].offset - halfWindow { lo += 1 }
        while hi + 1 < s.count && s[hi + 1].offset <= s[i].offset + halfWindow { hi += 1 }
        let v = s[lo...hi].map(\.bpm).sorted()
        let m = v.count / 2
        return v.count % 2 == 0 ? Double(v[m - 1] + v[m]) / 2 : Double(v[m])
    }
}
