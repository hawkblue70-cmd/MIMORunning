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
            .navigationTitle("미모러닝")
            .navigationBarTitleDisplayMode(.large)
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
                Image(systemName: "figure.run")
                    .font(.system(size: 72))
                    .foregroundStyle(Theme.violet)
                VStack(spacing: 8) {
                    Text("미모러닝")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("걷고 뛰기만 하세요.\n정리는 미모러닝이 합니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
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
    @State private var displayCount = 50
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
    }
}

// MARK: - Activity Card

private struct ActivityCard: View {
    let activity: Activity
    var level: LevelBucket = .beginner
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(activity.type.label, systemImage: activity.type.icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.violet)
                Spacer()
                Text(activity.date, format: .dateTime.month().day().hour().minute())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
            Text(activity.formattedDistance)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            HStack(spacing: 5) {
                MetricChip(value: activity.formattedDuration, label: "시간", color: Theme.time)
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
