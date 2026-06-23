import SwiftUI
import SwiftData
import PhotosUI
import StoreKit
#if canImport(ImagePlayground)
import ImagePlayground
#endif

// MARK: - File-private types

private struct BadgeInfo: Identifiable {
    let id: String
    let icon: String
    let title: String
    let achieved: Bool
    let achievedDate: Date?
}

// MARK: - MeView

struct MeView: View {
    var manager: HealthKitManager

    @Environment(CustomMiniMeStore.self) private var miniMeStore
    @Query private var shoes: [Shoe]
    @Query private var allStories: [WorkoutStory]
    @State private var showMonthlyShare = false
    @State private var showYearlyShare  = false
    @State private var showAddShoe = false
    @AppStorage("distanceUnitMiles") private var useMiles = false
    @AppStorage("garminNoticeDismissed") private var garminNoticeDismissed = false
    @AppStorage("showRunning")  private var showRunning  = true
    @AppStorage("showWalking")  private var showWalking  = false
    @AppStorage("showHiking")   private var showHiking   = false
    @AppStorage("showCycling")  private var showCycling  = false
    @AppStorage("showSwimming") private var showSwimming = false

    // MARK: - Period stats

    private var monthlyActivities: [Activity] {
        let cal = Calendar.current
        let now = Date()
        let year  = cal.component(.year,  from: now)
        let month = cal.component(.month, from: now)
        return manager.activities.filter {
            cal.component(.year,  from: $0.date) == year &&
            cal.component(.month, from: $0.date) == month
        }
    }

    private var yearlyActivities: [Activity] {
        let year = Calendar.current.component(.year, from: Date())
        return manager.activities.filter {
            Calendar.current.component(.year, from: $0.date) == year
        }
    }

    private var monthlyStats: SummaryPeriodStats {
        let now = Date()
        let cal = Calendar.current
        return SummaryPeriodStats(
            kind: .monthly(year: cal.component(.year, from: now),
                           month: cal.component(.month, from: now)),
            activities: monthlyActivities,
            useMiles: useMiles
        )
    }

    private var yearlyStats: SummaryPeriodStats {
        SummaryPeriodStats(
            kind: .yearly(year: Calendar.current.component(.year, from: Date())),
            activities: yearlyActivities,
            useMiles: useMiles
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        profileHeader
                        if manager.hasGarminSource && !garminNoticeDismissed {
                            garminNoticeSection
                        }
                        miniMeSection
                        statsSection
                        shoesSection
                        milestonesSection
                        settingsSection
                        Spacer(minLength: 32)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("나")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Garmin notice

    private var garminNoticeSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.violet)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("가민 기기 감지됨")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text("심박·러닝폼·VO2max 등 일부 지표는 가민→애플 건강 앱 동기화가 필요해요. 동기화가 안 된 경우 해당 지표가 표시되지 않을 수 있어요.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                withAnimation(.easeOut) { garminNoticeDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.violet.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.violet.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Profile header (미니미 자리)

    private var profileHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                if let customImg = miniMeStore.image {
                    Image(uiImage: customImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 84, height: 84)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.violet.opacity(0.5), lineWidth: 2))
                } else {
                    Circle()
                        .fill(Theme.violet.opacity(0.15))
                        .frame(width: 84, height: 84)
                    Image(systemName: "figure.run")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Theme.violet)
                }
            }
            Text("나의 러닝")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("\(manager.activities.count)개 활동 기록")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - MiniMe section

    private var miniMeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("내 미니미")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            #if canImport(ImagePlayground)
            if #available(iOS 18.2, *) {
                MiniMeCreatorView()
                    .padding(.horizontal, 16)
            } else {
                miniMeFallback
            }
            #else
            miniMeFallback
            #endif
        }
    }

    private var miniMeFallback: some View {
        HStack(spacing: 16) {
            MiniMeView(variant: .running, size: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text("기본 미니미")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("iOS 18.2 이상 기기에서 나만의 미니미를 만들 수 있어요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    // MARK: - Stats section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("기간별 결산")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            SummarySectionCard(stats: monthlyStats) { showMonthlyShare = true }
                .padding(.horizontal, 16)
            SummarySectionCard(stats: yearlyStats)  { showYearlyShare  = true }
                .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showMonthlyShare) {
            SummaryShareCardScreen(stats: monthlyStats, miniMeImage: miniMeStore.image)
        }
        .sheet(isPresented: $showYearlyShare) {
            SummaryShareCardScreen(stats: yearlyStats, miniMeImage: miniMeStore.image)
        }
    }

    // MARK: - Shoes section

    @Environment(\.modelContext) private var modelContext

    private func cumulativeKm(for shoe: Shoe) -> Double {
        let sid = shoe.id.uuidString
        let storyIDs = allStories.filter { $0.shoeID == sid }.map { $0.workoutID }
        let matched = manager.activities.filter { storyIDs.contains($0.id.uuidString) }
        return matched.reduce(0) { $0 + $1.distance } / 1000
    }

    private var shoesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("신발")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    showAddShoe = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.violet)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            if shoes.isEmpty {
                Text("등록된 신발이 없어요. + 버튼으로 추가하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shoes.enumerated()), id: \.element.id) { idx, shoe in
                        if idx > 0 { thinDivider }
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Theme.violet.opacity(0.15))
                                    .frame(width: 38, height: 38)
                                Image(systemName: "shoe.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Theme.violet)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shoe.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(shoe.addedDate, format: .dateTime.year().month().day())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            let km = cumulativeKm(for: shoe)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(String(format: km >= 100 ? "%.0f" : "%.1f", km))
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    .foregroundStyle(.white)
                                Text("km")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                modelContext.delete(shoe)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                }
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
            }
        }
        .sheet(isPresented: $showAddShoe) {
            AddShoeSheet()
        }
    }

    // MARK: - Milestones section

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("마일스톤")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(computeBadges()) { badge in
                    BadgeCell(badge: badge)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Settings section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("설정")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            // Subscription
            SubscriptionSectionCard()
                .padding(.horizontal, 16)

            // Activity type filter
            VStack(spacing: 0) {
                settingRow {
                    Text("활동 종류")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                thinDivider
                settingRow {
                    Label("러닝", systemImage: "figure.run").foregroundStyle(.white)
                    Spacer()
                    Toggle("", isOn: $showRunning).labelsHidden().tint(Theme.violet)
                }
                thinDivider
                settingRow {
                    Label("걷기", systemImage: "figure.walk").foregroundStyle(.white)
                    Spacer()
                    Toggle("", isOn: $showWalking).labelsHidden().tint(Theme.violet)
                }
                thinDivider
                settingRow {
                    Label("하이킹", systemImage: "figure.hiking").foregroundStyle(.white)
                    Spacer()
                    Toggle("", isOn: $showHiking).labelsHidden().tint(Theme.violet)
                }
                thinDivider
                settingRow {
                    Label("자전거", systemImage: "figure.outdoor.cycle").foregroundStyle(.white)
                    Spacer()
                    Toggle("", isOn: $showCycling).labelsHidden().tint(Theme.violet)
                }
                thinDivider
                settingRow {
                    Label("수영", systemImage: "figure.pool.swim").foregroundStyle(.white)
                    Spacer()
                    Toggle("", isOn: $showSwimming).labelsHidden().tint(Theme.violet)
                }
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)

            // Display preferences
            VStack(spacing: 0) {
                settingRow {
                    Text("거리 단위").foregroundStyle(.white)
                    Spacer()
                    Picker("", selection: $useMiles) {
                        Text("km").tag(false)
                        Text("마일").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                }
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)

            // HealthKit
            VStack(spacing: 0) {
                settingRow {
                    Label("건강 앱", systemImage: "heart.text.square").foregroundStyle(.white)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(manager.authorizationStatus == .authorized
                                  ? Theme.elevation : Theme.heartRate)
                            .frame(width: 7, height: 7)
                        Text(manager.authorizationStatus == .authorized ? "연결됨" : "미연결")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if manager.authorizationStatus != .authorized {
                    thinDivider
                    settingRow {
                        Button {
                            Task { await manager.requestAuthorization() }
                        } label: {
                            Text("권한 다시 요청")
                                .font(.subheadline)
                                .foregroundStyle(Theme.violet)
                        }
                        Spacer()
                    }
                }
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)

            // App info
            VStack(spacing: 0) {
                settingRow {
                    Text("앱 버전").foregroundStyle(.white)
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        .font(.caption).foregroundStyle(.secondary)
                }
                thinDivider
                settingRow {
                    Text("만든 곳").foregroundStyle(.white)
                    Spacer()
                    Text("MIMOPlanner").font(.caption).foregroundStyle(.secondary)
                }
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
        }
    }

    private func settingRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    // MARK: - Badge computation

    private func computeBadges() -> [BadgeInfo] {
        let all = manager.activities.sorted { $0.date < $1.date }
        let runs = all.filter { $0.type == .running }

        func firstRun(over dist: Double) -> Activity? { runs.first { $0.distance >= dist } }

        var badges: [BadgeInfo] = [
            .init(id: "first_run", icon: "figure.run",  title: "첫 러닝",
                  achieved: !runs.isEmpty,                        achievedDate: runs.first?.date),
            .init(id: "5k",   icon: "flag",        title: "5K 완주",
                  achieved: firstRun(over:  5000) != nil,         achievedDate: firstRun(over:  5000)?.date),
            .init(id: "10k",  icon: "flag.fill",   title: "10K 완주",
                  achieved: firstRun(over: 10000) != nil,         achievedDate: firstRun(over: 10000)?.date),
            .init(id: "half", icon: "medal",        title: "하프 완주",
                  achieved: firstRun(over: 21097) != nil,         achievedDate: firstRun(over: 21097)?.date),
            .init(id: "full", icon: "trophy.fill",  title: "풀 완주",
                  achieved: firstRun(over: 42195) != nil,         achievedDate: firstRun(over: 42195)?.date),
        ]

        // Cumulative distance (all activity types)
        var totalKm = 0.0
        var cumDates: [Int: Date] = [:]
        for a in all {
            totalKm += a.distance / 1000
            for t in [100, 300, 500, 1000] where cumDates[t] == nil && totalKm >= Double(t) {
                cumDates[t] = a.date
            }
        }
        badges += [
            .init(id: "cum100",  icon: "map",           title: "누적 100km",
                  achieved: cumDates[100]  != nil, achievedDate: cumDates[100]),
            .init(id: "cum300",  icon: "map.fill",       title: "누적 300km",
                  achieved: cumDates[300]  != nil, achievedDate: cumDates[300]),
            .init(id: "cum500",  icon: "globe.americas", title: "누적 500km",
                  achieved: cumDates[500]  != nil, achievedDate: cumDates[500]),
            .init(id: "cum1000", icon: "globe",          title: "누적 1000km",
                  achieved: cumDates[1000] != nil, achievedDate: cumDates[1000]),
        ]

        // Week streak
        let maxStreak = computeMaxWeekStreak(runs: runs)
        badges += [
            .init(id: "streak4",  icon: "flame.fill", title: "4주 연속",  achieved: maxStreak >= 4,  achievedDate: nil),
            .init(id: "streak8",  icon: "bolt.fill",  title: "8주 연속",  achieved: maxStreak >= 8,  achievedDate: nil),
            .init(id: "streak12", icon: "crown.fill", title: "12주 연속", achieved: maxStreak >= 12, achievedDate: nil),
        ]

        return badges
    }

    private func computeMaxWeekStreak(runs: [Activity]) -> Int {
        guard !runs.isEmpty else { return 0 }
        let cal = Calendar.current
        let weekStarts = Set(runs.map {
            cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0.date))!
        }).sorted()
        var maxStreak = 1, cur = 1
        for i in 1..<weekStarts.count {
            let days = cal.dateComponents([.day], from: weekStarts[i - 1], to: weekStarts[i]).day ?? 0
            if days == 7 { cur += 1 } else { cur = 1 }
            if cur > maxStreak { maxStreak = cur }
        }
        return maxStreak
    }
}

// MARK: - Summary section card (inline in Me tab)

private struct SummarySectionCard: View {
    let stats: SummaryPeriodStats
    let onShare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(stats.kind.subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.violet)
                }
                Spacer()
                Button(action: onShare) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                        Text("공유")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.violet)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.violet.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(stats.isEmpty)
                .opacity(stats.isEmpty ? 0.35 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            // Stats grid
            if stats.isEmpty {
                Text("이 기간에 기록된 활동이 없어요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                HStack(spacing: 0) {
                    statCell(
                        value: stats.distanceStr + " " + stats.distanceUnit,
                        label: "총 거리",
                        color: .white
                    )
                    cellDivider
                    statCell(
                        value: stats.durationStr,
                        label: "운동 시간",
                        color: Theme.time
                    )
                    cellDivider
                    statCell(
                        value: "\(stats.runCount)회",
                        label: "러닝",
                        color: Theme.violet
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if let pace = stats.avgPaceStr {
                    HStack(spacing: 6) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.pace.opacity(0.7))
                        Text("평균 페이스")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(pace)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        if let longest = stats.longestStr {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text("최장 \(longest)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }

            Spacer(minLength: 14)
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func statCell(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cellDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 0.5, height: 28)
            .padding(.horizontal, 10)
    }
}

// MARK: - Badge Cell

private struct BadgeCell: View {
    let badge: BadgeInfo

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(badge.achieved ? Theme.violet.opacity(0.18) : Color.white.opacity(0.05))
                    .frame(width: 52, height: 52)
                Image(systemName: badge.icon)
                    .font(.system(size: 22, weight: badge.achieved ? .semibold : .light))
                    .foregroundStyle(badge.achieved ? Theme.violet : Color.white.opacity(0.2))
            }
            Text(badge.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(badge.achieved ? .white : Color.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if let date = badge.achievedDate {
                    Text(shortDate(date))
                        .foregroundStyle(.secondary)
                } else if badge.achieved {
                    Text("달성").foregroundStyle(Theme.violet.opacity(0.8))
                } else {
                    Text("미달성").foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 9))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func shortDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yy.M.d"
        return fmt.string(from: date)
    }
}

// MARK: - MiniMe creator (iOS 18.2+, Apple Intelligence)

#if canImport(ImagePlayground)
@available(iOS 18.2, *)
private struct MiniMeCreatorView: View {
    @Environment(CustomMiniMeStore.self) private var miniMeStore
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground

    @State private var pickerItem: PhotosPickerItem?
    @State private var sourceUIImage: UIImage?
    @State private var showPlayground = false

    var body: some View {
        VStack(spacing: 10) {
            currentPreview

            if supportsImagePlayground {
                creatorButtons
            } else {
                Text("Apple Intelligence가 지원되는 기기(iPhone 15 Pro 이상, iOS 18.2+)에서 나만의 미니미를 만들 수 있어요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            Task {
                guard let item = newItem,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data) else { return }
                sourceUIImage = img
                showPlayground = true
            }
        }
        .imagePlaygroundSheet(
            isPresented: $showPlayground,
            concepts: [.text("러너, 귀여운 캐릭터, 바이올렛 색깔, 만화체, 밝고 귀여운 스타일")],
            sourceImage: sourceUIImage.map { Image(uiImage: $0) }
        ) { url in
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                miniMeStore.save(img)
            }
            showPlayground = false
            pickerItem = nil
            sourceUIImage = nil
        }
    }

    private var currentPreview: some View {
        HStack(spacing: 16) {
            if let img = miniMeStore.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.violet.opacity(0.5), lineWidth: 2))
            } else {
                MiniMeView(variant: .running, size: 64)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(miniMeStore.image != nil ? "내 미니미" : "기본 미니미")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(miniMeStore.image != nil
                     ? "인사이트·공유 카드에 표시돼요"
                     : "사진으로 나만의 미니미를 만들어 보세요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var creatorButtons: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label(miniMeStore.image != nil ? "다시 만들기" : "사진으로 만들기",
                      systemImage: miniMeStore.image != nil ? "arrow.clockwise" : "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if miniMeStore.image != nil {
                Button {
                    miniMeStore.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
#endif

// MARK: - Subscription Card

struct SubscriptionSectionCard: View {
    @ObservedObject private var pro = ProManager.shared

    private var product: Product? { pro.products.first(where: { $0.id == ProManager.sixMonthID }) }
    private var isEligibleForIntro: Bool { pro.introEligibility[ProManager.sixMonthID] == true }

    private var introOfferLabel: String {
        guard let offer = product?.subscription?.introductoryOffer else { return "무료 체험" }
        let v = offer.period.value
        switch offer.period.unit {
        case .day:   return "\(v)일 무료"
        case .week:  return "\(v)주 무료"
        case .month: return "\(v)개월 무료"
        case .year:  return "\(v)년 무료"
        @unknown default: return "무료 체험"
        }
    }

    @State private var isPurchasing = false

    var body: some View {
        VStack(spacing: 0) {
            // Header gradient band
            LinearGradient(
                colors: [Theme.violet, Color(hex: "5B3FD6")],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 4)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 14, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 14
            ))

            VStack(spacing: 14) {
                // Title row
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.violet)
                    Text("MIMO Pro")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    if pro.isPro {
                        Text("구독 중")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.violet)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.violet.opacity(0.15))
                            .clipShape(Capsule())
                    } else if pro.isTrialActive {
                        Text("체험 \(pro.daysRemainingInTrial)일 남음")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    } else {
                        Text("체험 종료")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                // Price block
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(product?.displayPrice ?? "₩11,000")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("/ 6개월")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)
                    Spacer()
                    if isEligibleForIntro {
                        Text(introOfferLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.violet)
                    } else {
                        Text("월 ₩1,833")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                // CTA
                if !pro.isPro {
                    Button {
                        Task { await doPurchase() }
                    } label: {
                        Group {
                            if isPurchasing {
                                ProgressView().tint(.white)
                            } else {
                                Text(isEligibleForIntro ? "무료로 시작하기" : "구독하기")
                                    .font(.system(size: 15, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing || product == nil)
                    .opacity((isPurchasing || product == nil) ? 0.6 : 1)

                    Button {
                        Task { await pro.restorePurchases() }
                    } label: {
                        Text("구독 복원")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }

                if let err = pro.purchaseError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(Theme.heartRate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let err = pro.productLoadError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(Theme.heartRate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Legal
                VStack(spacing: 6) {
                    Text("구독은 기간 종료 24시간 전까지 취소하지 않으면 자동 갱신됩니다. Apple ID 계정을 통해 관리할 수 있습니다.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Link("개인정보처리방침",
                             destination: URL(string: "https://mimoplanner.kr/privacy.html")!)
                        Text("·").foregroundStyle(.tertiary)
                        Link("이용약관",
                             destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Theme.cardBackground)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 14,
                bottomTrailingRadius: 14, topTrailingRadius: 0
            ))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .task {
            await pro.loadProducts()
        }
    }

    private func doPurchase() async {
        guard let product else { return }
        isPurchasing = true
        _ = await pro.purchase(product)
        isPurchasing = false
    }
}

// MARK: - Add Shoe Sheet

private struct AddShoeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var brand = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        field(label: "신발 이름", placeholder: "예: Pegasus 41", text: $name)
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 0.5)
                            .padding(.horizontal, 16)
                        field(label: "브랜드 (선택)", placeholder: "예: Nike", text: $brand)
                    }
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)

                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationTitle("신발 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("추가") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let shoe = Shoe(name: name.trimmingCharacters(in: .whitespaces),
                                       brand: brand.trimmingCharacters(in: .whitespaces))
                        modelContext.insert(shoe)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? Color.white.opacity(0.3) : Theme.violet)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func field(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}
