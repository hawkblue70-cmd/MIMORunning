import Foundation

// MARK: - 모델 버전

/// 계산식이 바뀔 때마다 current를 +1 한다.
/// [파생] 캐시 키 맨 앞에 prefix("m{N}_")를 붙여 구버전 캐시와 자동 격리.
///
/// 히스토리:
///   1 — 최초 포팅
///   2 — LT1 0.785/0.800, HRmax 관측 상위5 중앙값,
///       더위 모델 심박 공변량 제거, 마라톤 지수 v3(롱런 계단+Tanda),
///       드리프트 세션 중심화, 테이퍼 2주 지수,
///       인터벌 판정 앱 기존 로직 통일, 폼 문구 개편
///   3 — 하프 대회 페이스 단계 + 롱런 후반 구간 문구
enum MRModelVersion {
    static let current = 3
    static var prefix: String { "m\(current)_" }

    // ★ prefix 를 붙이면 안 되는 것 — 모델과 무관한 원본 또는 사용자 이력
    //   mimo.workoutTypeCache.v1  — 앱 기존 판정, 모델이 바뀌어도 재분류 불필요
    //   mimo_panel_*              — 시계열 원본 (HK에서 읽은 것, 재계산 불필요)
    //   LevelEngine 레벨 버킷     — 사용자 이력 (강등 방지 목적)
    //   mimo_insight_theme_history — 사용자 이력
    //   mimo.adviceLog.v2         — 사용자 이력 (신선도·반복 방지)
}

// MARK: - 캐시 정리 (MainActor 전용)

/// 앱 시작 시 1회 호출. Caches 디렉터리에서 구버전 [파생] 캐시를 삭제한다.
/// ⚠ [원본] 캐시(workouts/steps/HR 등)·사용자 이력(어드바이스/레벨)은 건드리지 않는다.
///
/// MRModelVersion 에서 분리한 이유:
///   purgeStaleCaches 를 같은 enum 에 두면 @main init() 에서의 호출로 인해
///   Swift 가 MRModelVersion 전체를 @MainActor 로 추론한다.
///   prefix/current 가 @MainActor 가 되면 nonisolated 컨텍스트(InsightCache 등)에서
///   참조 시 경고가 발생한다. 별도 @MainActor enum 으로 분리해 오염을 차단.
enum MRCacheMaintenance {
    static func purgeStale() {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]

        // ① prefix 없던 시절 드리프트·백테스트 파일
        for name in ["mr_drift_cache.json", "mr_backtest_cache.json"] {
            try? fm.removeItem(at: caches.appendingPathComponent(name))
        }

        // ② mX_ prefix는 있지만 현재 버전이 아닌 파일 (m1_, m3_, ...)
        if let files = try? fm.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil) {
            for url in files {
                let name = url.lastPathComponent
                // "m" + 숫자 + "_" 패턴이되 현재 prefix(m2_)가 아닌 것
                if name.count >= 3,
                   name.hasPrefix("m"),
                   name.dropFirst().first?.isNumber == true,
                   !name.hasPrefix(MRModelVersion.prefix) {
                    try? fm.removeItem(at: url)
                }
            }
        }

        purgeStaleDetailCaches(fm)
        purgeStaleRouteCardMaps(fm, caches: caches)
    }

    /// ③ 옛 버전 상세 캐시 — 버전을 올릴 때마다 러닝 한 건당 한 벌씩 쌓인다.
    /// Application Support에 있어 iOS가 알아서 비우지 않고 백업에도 들어간다.
    /// 지워도 HealthKit에서 다시 만든다.
    private static func purgeStaleDetailCaches(_ fm: FileManager) {
        let dir = HealthKitManager.detailCacheDirectory
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files {
            let name = url.lastPathComponent
            guard name.hasSuffix(".json"),
                  let version = versionPrefix(of: name),
                  version != HealthKitManager.detailCacheVersion else { continue }
            try? fm.removeItem(at: url)
        }
    }

    /// ④ 옛 버전 경로 지도 스냅샷 — 상세 화면 것과 카드 것 모두. 지금 쓰는 버전만 남긴다.
    /// 지워도 다음에 열 때 다시 찍는다.
    ///
    /// 이름이 긴 앞자리부터 봐야 한다 — "mimo_map_card_"와 "mimo_map_hrzone_"은
    /// 둘 다 "mimo_map_"으로 시작해서, 순서를 바꾸면 카드 캐시를 상세 캐시로 잘못 읽는다.
    private static func purgeStaleRouteCardMaps(_ fm: FileManager, caches: URL) {
        let groups: [(prefix: String, keep: Set<String>)] = [
            (RouteCardStyle.mapCachePrefix, Set(RouteCardStyle.allCases.map(\.mapCacheVersion))),
            (RouteMapCache.zonePrefix,      Set([RouteMapCache.zoneVersion])),
            (RouteMapCache.plainPrefix,     Set([RouteMapCache.plainVersion])),
        ].sorted { $0.prefix.count > $1.prefix.count }

        guard let files = try? fm.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil) else { return }
        for url in files {
            let name = url.lastPathComponent
            guard name.hasSuffix(".jpg"),
                  let group = groups.first(where: { name.hasPrefix($0.prefix) }),
                  let version = versionPrefix(of: String(name.dropFirst(group.prefix.count))),
                  !group.keep.contains(version) else { continue }
            try? fm.removeItem(at: url)
        }
    }

    /// "v15_ABC.json" → "v15". 첫 밑줄 앞이 "v"로 시작하고 숫자를 포함할 때만 — 못 읽으면 nil(건드리지 않음).
    /// 파일 이름을 잘못 읽어 현재 캐시를 지우는 일이 없도록 판정을 좁게 잡는다.
    private static func versionPrefix(of name: String) -> String? {
        guard let underscore = name.firstIndex(of: "_") else { return nil }
        let version = String(name[name.startIndex..<underscore])
        guard version.count >= 2, version.hasPrefix("v"),
              version.dropFirst().contains(where: \.isNumber),
              version.dropFirst().allSatisfy({ $0.isNumber || $0.isLetter }) else { return nil }
        return version
    }
}

// MARK: - 워크아웃 한 건
//
// HealthKit에서 읽어온 러닝 한 건. 계산 엔진은 이 타입만 본다.
// (HealthKit 의존성을 여기서 끊어야 테스트에 가짜 데이터를 넣을 수 있다)
struct MRWorkout: Codable, Sendable {
    let start: Date
    let durationMin: Double
    let distanceKm: Double?
    let hrAvg: Double?
    let hrMax: Double?
    let tempC: Double?          // HKWeatherTemperature
    let humidity: Double?       // 0~100
    let indoor: Bool

    /// 구조화된 인터벌 세션인가.
    ///
    /// ⚠ 이 값이 필요한 이유는 두 가지다:
    ///   ① 인터벌은 평균 심박이 높아 대회급 노력 게이트를 통과한다.
    ///      하지만 인터벌의 **평균 페이스는 대회 페이스가 아니다**
    ///      (질주 구간 + 회복 구간의 평균이다).
    ///      지수 회귀에 넣으면 개인 지수가 오염된다.
    ///   ② 의도한 고강도를 "이지를 너무 빠르게 뛴 것"으로 세면 안 된다.
    ///      인터벌 1회 + 이지 3회는 건강한 구성이지 문제가 아니다.
    let isInterval: Bool

    var date: Date {
        Calendar.current.startOfDay(for: start)
    }

    /// 초/km
    var paceSecPerKm: Double? {
        guard let d = distanceKm, d > 0 else { return nil }
        return durationMin * 60.0 / d
    }

    /// m/min
    var speedMPerMin: Double? {
        guard let d = distanceKm, durationMin > 0 else { return nil }
        return d * 1000.0 / durationMin
    }
}

// MARK: - 확신도
//
// 모든 추정치는 "얼마나 믿을 만한가"를 같이 들고 다닌다.
// 불확실할 때 불확실하다고 말하는 것이 이 앱의 원칙이다.
enum MRConfidence: Int, Comparable {
    case none = 0, low, medium, high

    var label: String {
        switch self {
        case .none:   return "없음"
        case .low:    return "낮음"
        case .medium: return "보통"
        case .high:   return "높음"
        }
    }

    static func < (a: MRConfidence, b: MRConfidence) -> Bool {
        a.rawValue < b.rawValue
    }
}

// MARK: - 근거를 달고 다니는 추정치
//
// basis는 UI에 그대로 노출한다. 사용자가 탭하면 왜 이 숫자인지 볼 수 있어야 한다.
struct MRInference {
    let value: Double
    let confidence: MRConfidence
    let basis: [String]
}

// MARK: - 대회급 노력
//
// 실제 대회이거나, 대회에 준하는 강도로 달린 기록.
// 지수 적합과 예측의 재료가 된다.
struct MRRaceEffort: Sendable {
    let date: Date
    let distanceM: Double
    let timeMin: Double
    var timeMinRef: Double      // 기온 15°C 기준으로 환산한 값
    let tempC: Double?
    let label: String           // "10K" / "하프" / "풀" / "12.4K"
    let isConfirmedRace: Bool   // 대회 매칭으로 확정된 건인지

    var vdot: Double {
        MIMORunning.vdot(distanceM: distanceM, timeMin: timeMin)
    }
}

// MARK: - 예측 결과
struct MRPrediction {
    let label: String
    let distanceM: Double
    let midMin: Double
    let loMin: Double
    let hiMin: Double
    let confidence: MRConfidence
    let basis: [String]
}

// MARK: - 시간 포맷
func mrFormatHMS(_ minutes: Double) -> String {
    let total = Int((minutes * 60).rounded())
    return String(format: "%d:%02d:%02d",
                  total / 3600, (total % 3600) / 60, total % 60)
}

/// 사람에게 보여줄 때 쓰는 포맷. 한 시간 미만이면 시(時)를 떼어낸다.
/// (`mrFormatHMS`는 계산·검증용이라 그대로 둔다)
func mrFormatDisplay(_ minutes: Double) -> String {
    let total = Int((minutes * 60).rounded())
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return AppLanguage.shared.isEnglish
        ? String(format: "%d:%02d", m, s)
        : String(format: "%d분 %02d초", m, s)
}

func mrFormatPace(_ secPerKm: Double) -> String {
    // ⚠ 버림(Int, 반올림 아님) + '/" 기호 — Activity.formattedPace와 동일.
    //   반올림이 다르면 같은 러닝이 목록에서 6'28"인데 카드에서 6:29로 보인다.
    let s = Int(secPerKm)
    return String(format: "%d'%02d\"", s / 60, s % 60)
}
