import SwiftUI
import SwiftData

struct ActivityListView: View {
    var manager: HealthKitManager

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                switch manager.authorizationStatus {
                case .notDetermined:
                    ConnectView {
                        Task { await manager.requestAuthorization() }
                    }
                case .authorized:
                    ActivityListContent(manager: manager)
                case .denied:
                    UnavailableView()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Activity.self) { activity in
                ActivityDetailView(activity: activity, manager: manager)
            }
        }
    }
}

// MARK: - Connect Screen

private struct ConnectView: View {
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "3DFF7A").opacity(0.12))
                        .frame(width: 108, height: 108)
                    Image(systemName: "figure.run")
                        .font(.system(size: 56))
                        .foregroundStyle(Color(hex: "3DFF7A"))
                }
                VStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("MIMO")
                            .font(.system(size: 58, weight: .black))
                            .fontWidth(.condensed)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Theme.violet, Color(red: 0.72, green: 0.52, blue: 1.0)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text("Running")
                            .font(.system(size: 40, weight: .black))
                            .fontWidth(.condensed)
                            .foregroundStyle(.white)
                            .tracking(2)
                    }
                    Text(AppLanguage.shared.s("걷고 뛰기만 하세요.\n정리는 MIMO Running이 합니다.",
                                              "Just walk and run.\nMIMO Running handles the rest."))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
            }
            Spacer()
            Button(action: onConnect) {
                Text(AppLanguage.shared.s("건강 앱 연결하기", "Connect Health App"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }
}

// MARK: - Activity List

private struct ActivityListContent: View {
    var manager: HealthKitManager
    @Environment(RaceDetector.self) private var raceDetector
    @ObservedObject private var pro = ProManager.shared
    @State private var displayCount = 50
    @State private var showPaywall = false
    @AppStorage("showRunning")  private var showRunning  = true
    @AppStorage("showWalking")  private var showWalking  = false
    @AppStorage("showHiking")   private var showHiking   = false

    @Query private var stories: [WorkoutStory]
    @Query private var shoes: [Shoe]

    private var shoeByWorkout: [String: String] {
        let shoeDict = Dictionary(uniqueKeysWithValues: shoes.map { ($0.id.uuidString, $0.displayName) })
        var result: [String: String] = [:]
        for story in stories {
            if let sid = story.shoeID, let name = shoeDict[sid] {
                result[story.workoutID] = name
            }
        }
        return result
    }

    private var filteredActivities: [Activity] {
        manager.activities.filter { a in
            switch a.type {
            case .running:  return showRunning
            case .walking:  return showWalking
            case .hiking:   return showHiking
            case .cycling:  return false
            case .swimming: return false
            }
        }
    }

    private var visibleActivities: [Activity] {
        Array(filteredActivities.prefix(displayCount))
    }

    var body: some View {
        Group {
            if manager.isLoading && manager.activities.isEmpty {
                ProgressView().tint(Theme.violet)
            } else if manager.activities.isEmpty {
                EmptyActivitiesView()
            } else if filteredActivities.isEmpty {
                FilteredEmptyView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        HStack(spacing: 0) {
                            Text("MIMO")
                                .font(.system(size: 38, weight: .black))
                                .fontWidth(.condensed)
                                .foregroundStyle(Theme.violet)
                            Text(" Running")
                                .font(.system(size: 38, weight: .black))
                                .fontWidth(.condensed)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)
                        if !pro.isPro {
                            TrialBannerView(
                                isExpired: pro.isTrialExpired,
                                daysRemaining: pro.daysRemainingInTrial
                            ) { showPaywall = true }
                        }
                        ForEach(visibleActivities) { activity in
                            NavigationLink(value: activity) {
                                ActivityCard(
                                    activity: activity,
                                    level: manager.userLevel.bucket,
                                    shoeName: shoeByWorkout[activity.id.uuidString],
                                    workoutType: manager.cachedWorkoutType(for: activity.id),
                                    raceName: raceDetector.matchFor(activityID: activity.id).flatMap {
                                        $0.isConfirmed ? $0.raceName : nil
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        if displayCount < filteredActivities.count {
                            Button {
                                displayCount += 50
                            } label: {
                                Text(AppLanguage.shared.s("더 보기 (\(filteredActivities.count - displayCount)개 남음)", "Load More (\(filteredActivities.count - displayCount) left)"))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.violet)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Theme.violet.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .refreshable {
                    displayCount = 50
                    manager.invalidateAllMetricHistoryCache()
                    await manager.fetchActivities(forced: true)
                }
            }
        }
        .onChange(of: showRunning)  { _, _ in displayCount = 50 }
        .onChange(of: showWalking)  { _, _ in displayCount = 50 }
        .onChange(of: showHiking)   { _, _ in displayCount = 50 }
        .sheet(isPresented: $showPaywall) {
            ProPaywallSheet()
        }
    }
}

// MARK: - Trial Banner

private struct TrialBannerView: View {
    let isExpired: Bool
    let daysRemaining: Int
    let onSubscribe: () -> Void

    private var accentColor: Color { isExpired ? .orange : Theme.violet }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isExpired ? "lock.fill" : "crown.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(isExpired
                     ? AppLanguage.shared.s("무료 체험이 종료되었어요", "Free trial ended")
                     : AppLanguage.shared.s("무료 체험 중 · \(daysRemaining)일 남음", "Free trial · \(daysRemaining) days left"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(isExpired
                     ? AppLanguage.shared.s("새 기록을 받으려면 MIMO Pro 구독이 필요해요", "Subscribe to MIMO Pro to keep syncing new workouts")
                     : AppLanguage.shared.s("체험 종료 후 새 기록을 계속 받으려면 구독하세요", "Subscribe to continue syncing after the trial"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action: onSubscribe) {
                Text(AppLanguage.shared.s("구독하기", "Subscribe"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accentColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(accentColor.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(accentColor.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Pro Paywall Sheet

private struct ProPaywallSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct FeatureRow: View {
        let icon: String
        let text: String
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.violet)
                    .frame(width: 20)
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Theme.violet.opacity(0.15))
                                    .frame(width: 72, height: 72)
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundStyle(Theme.violet)
                            }
                            Text("MIMO Pro")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                            Text(AppLanguage.shared.s("새 기록을 계속 쌓으려면\n구독이 필요해요", "Subscribe to keep syncing\nnew workouts"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 8)

                        // Features list
                        VStack(alignment: .leading, spacing: 12) {
                            Text(AppLanguage.shared.s("포함 기능", "What's included"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            FeatureRow(
                                icon: "arrow.triangle.2.circlepath",
                                text: AppLanguage.shared.s("모든 러닝·걷기·하이킹 기록 무제한 동기화", "Unlimited sync for all running, walking & hiking")
                            )
                            FeatureRow(
                                icon: "chart.xyaxis.line",
                                text: AppLanguage.shared.s("상세 지표: 페이스, 심박수, 칼로리, 고도", "Detailed metrics: pace, heart rate, calories, elevation")
                            )
                            FeatureRow(
                                icon: "map",
                                text: AppLanguage.shared.s("GPS 루트 지도 및 스플릿 분석", "GPS route map & split analysis")
                            )
                            FeatureRow(
                                icon: "sparkles",
                                text: AppLanguage.shared.s("러닝 인사이트 및 공유 카드", "Running insights & share cards")
                            )
                            FeatureRow(
                                icon: "shoe",
                                text: AppLanguage.shared.s("신발 관리 및 주행거리 추적", "Shoe management & mileage tracking")
                            )
                            FeatureRow(
                                icon: "chart.line.uptrend.xyaxis",
                                text: AppLanguage.shared.s("성장 차트 및 개인 기록(PR) 추적", "Growth charts & personal record (PR) tracking")
                            )
                        }
                        .padding(16)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)

                        SubscriptionSectionCard()
                            .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Activity Card

private struct ActivityCard: View {
    let activity: Activity
    var level: LevelBucket = .beginner
    var shoeName: String? = nil
    var workoutType: WorkoutType? = nil
    var raceName: String? = nil

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "yyyy. M. d h:mm a"
        return df
    }()

    private var formattedDate: String {
        Self.dateFormatter.string(from: activity.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                HStack(spacing: 4) {
                    Image(systemName: activity.type.icon)
                        .foregroundStyle(Color(hex: "3DFF7A"))
                    Text(activity.type.label)
                        .foregroundStyle(Theme.violet)
                    if let wt = workoutType {
                        Text("- \(wt.koreanLabel)")
                            .foregroundStyle(Color(hex: "FFC74D"))
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formattedDate)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    if let race = raceName {
                        Text(race)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(hex: "FFC74D"))
                            .lineLimit(1)
                    }
                }
            }
            Text(activity.formattedDistance)
                .font(.system(size: 24, weight: .black))
                .fontWidth(.condensed)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            HStack(spacing: 5) {
                switch activity.type {
                case .cycling:
                    if let speed = activity.formattedSpeed {
                        MetricChip(value: speed, label: "km/h", color: Theme.pace)
                    }
                case .swimming:
                    if let pace = activity.formattedPace100m {
                        MetricChip(value: pace, label: "/100m", color: Theme.pace)
                    }
                default:
                    if level >= .novice, let pace = activity.formattedPace {
                        MetricChip(value: pace, label: "/km", color: Theme.pace)
                    }
                }
                MetricChip(value: activity.formattedDuration, label: AppLanguage.shared.s("시간", "TIME"), color: Theme.time)
                if level >= .novice, let hr = activity.avgHeartRate {
                    MetricChip(value: "\(hr)", label: "bpm", color: Theme.heartRate)
                }
                if level >= .intermediate, activity.type != .swimming,
                   let cal = activity.calories {
                    MetricChip(value: String(format: "%.0f", cal), label: "kcal", color: Theme.calories)
                }
                if let shoe = shoeName {
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "shoe.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.secondary)
                        Text(shoe)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Metric Chip

private struct MetricChip: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 1) {
            Text(value)
                .font(.system(size: 9, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Empty / Unavailable

private struct EmptyActivitiesView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(AppLanguage.shared.s("기록된 활동이 없어요", "No activities found"))
                .foregroundStyle(.secondary)
        }
    }
}

private struct FilteredEmptyView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(AppLanguage.shared.s("선택한 종류의 활동이 없어요", "No activities for selected type"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(AppLanguage.shared.s("나 탭 > 설정 > 활동 종류에서 변경할 수 있어요", "Change in Me > Settings > Activity Type"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

private struct UnavailableView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundStyle(Theme.heartRate)
            Text(AppLanguage.shared.s("건강 앱을 사용할 수 없어요", "Health App Not Available"))
                .font(.headline)
                .foregroundStyle(.white)
            Text(AppLanguage.shared.s("이 기기는 HealthKit을 지원하지 않습니다.", "This device doesn't support HealthKit."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}
