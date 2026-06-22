import SwiftUI

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
                        .fill(Theme.violet.opacity(0.15))
                        .frame(width: 108, height: 108)
                    Image(systemName: "figure.run")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.violet)
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
                    Text("걷고 뛰기만 하세요.\n정리는 MIMO Running이 합니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
            }
            Spacer()
            Button(action: onConnect) {
                Text("건강 앱 연결하기")
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
    @ObservedObject private var pro = ProManager.shared
    @State private var displayCount = 50
    @State private var showPaywall = false
    @AppStorage("showRunning")  private var showRunning  = true
    @AppStorage("showWalking")  private var showWalking  = false
    @AppStorage("showHiking")   private var showHiking   = false
    @AppStorage("showCycling")  private var showCycling  = false
    @AppStorage("showSwimming") private var showSwimming = false

    private var filteredActivities: [Activity] {
        manager.activities.filter { a in
            switch a.type {
            case .running:  return showRunning
            case .walking:  return showWalking
            case .hiking:   return showHiking
            case .cycling:  return showCycling
            case .swimming: return showSwimming
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
                                ActivityCard(activity: activity, level: manager.userLevel.bucket)
                            }
                            .buttonStyle(.plain)
                        }
                        if displayCount < filteredActivities.count {
                            Button {
                                displayCount += 50
                            } label: {
                                Text("더 보기 (\(filteredActivities.count - displayCount)개 남음)")
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
                    await manager.fetchActivities()
                }
            }
        }
        .onChange(of: showRunning)  { _, _ in displayCount = 50 }
        .onChange(of: showWalking)  { _, _ in displayCount = 50 }
        .onChange(of: showHiking)   { _, _ in displayCount = 50 }
        .onChange(of: showCycling)  { _, _ in displayCount = 50 }
        .onChange(of: showSwimming) { _, _ in displayCount = 50 }
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
                     ? "무료 체험이 종료되었어요"
                     : "무료 체험 중 · \(daysRemaining)일 남음")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(isExpired
                     ? "새 기록을 받으려면 MIMO Pro 구독이 필요해요"
                     : "체험 종료 후 새 기록을 계속 받으려면 구독하세요")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action: onSubscribe) {
                Text("구독하기")
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

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
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
                            Text("새 기록을 계속 쌓으려면\n구독이 필요해요")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 8)

                        SubscriptionSectionCard()
                            .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
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

    private var formattedDate: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "yyyy. M. d h:mm a"
        return df.string(from: activity.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(activity.type.label, systemImage: activity.type.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.violet)
                Spacer()
                Text(formattedDate)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
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
                MetricChip(value: activity.formattedDuration, label: "시간", color: Theme.time)
                if level >= .novice, let hr = activity.avgHeartRate {
                    MetricChip(value: "\(hr)", label: "bpm", color: Theme.heartRate)
                }
                if level >= .intermediate, activity.type != .swimming,
                   let cal = activity.calories {
                    MetricChip(value: String(format: "%.0f", cal), label: "kcal", color: Theme.calories)
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
            Text("기록된 활동이 없어요")
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
            Text("선택한 종류의 활동이 없어요")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("나 탭 > 설정 > 활동 종류에서 변경할 수 있어요")
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
            Text("건강 앱을 사용할 수 없어요")
                .font(.headline)
                .foregroundStyle(.white)
            Text("이 기기는 HealthKit을 지원하지 않습니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}
