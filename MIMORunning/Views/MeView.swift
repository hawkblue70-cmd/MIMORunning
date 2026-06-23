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
    @State private var showShare0 = false
    @State private var showShare1 = false
    @State private var showShare2 = false
    @State private var showYearShare0 = false
    @State private var showYearShare1 = false
    @State private var showAddShoe = false
    @State private var shoeToDelete: Shoe?
    @AppStorage("distanceUnitMiles") private var useMiles = false
    @AppStorage("garminNoticeDismissed") private var garminNoticeDismissed = false
    @AppStorage("showRunning")  private var showRunning  = true
    @AppStorage("showWalking")  private var showWalking  = false
    @AppStorage("showHiking")   private var showHiking   = false

    // MARK: - Period stats

    private var runWalkActivities: [Activity] {
        manager.activities.filter { $0.type == .running || $0.type == .walking }
    }

    private func periodStats(monthOffset: Int) -> SummaryPeriodStats {
        let cal = Calendar.current
        let ref = cal.date(byAdding: .month, value: -monthOffset, to: Date()) ?? Date()
        let year  = cal.component(.year,  from: ref)
        let month = cal.component(.month, from: ref)
        let acts = runWalkActivities.filter {
            cal.component(.year,  from: $0.date) == year &&
            cal.component(.month, from: $0.date) == month
        }

        let prevRef = cal.date(byAdding: .month, value: -(monthOffset + 1), to: Date()) ?? Date()
        let prevYear  = cal.component(.year,  from: prevRef)
        let prevMonth = cal.component(.month, from: prevRef)
        let prevActs = runWalkActivities.filter {
            cal.component(.year,  from: $0.date) == prevYear &&
            cal.component(.month, from: $0.date) == prevMonth
        }
        let prevRuns = prevActs.filter { $0.type == .running }
        let prevDistKm = prevActs.reduce(0.0) { $0 + $1.distance / 1000 }
        let prevPaceSec: Double? = {
            let r = prevRuns.filter { $0.distance > 0 }
            guard !r.isEmpty else { return nil }
            let d = r.reduce(0.0) { $0 + $1.distance }
            let t = r.reduce(0.0) { $0 + $1.duration }
            return d > 0 ? t / (d / 1000) : nil
        }()

        var ytdKm: Double? = nil
        if monthOffset == 0 {
            let currYear = cal.component(.year, from: Date())
            let km = runWalkActivities.filter {
                cal.component(.year, from: $0.date) == currYear
            }.reduce(0.0) { $0 + $1.distance / 1000 }
            ytdKm = km > 0 ? km : nil
        }

        return SummaryPeriodStats(
            kind: .monthly(year: year, month: month),
            activities: acts,
            useMiles: useMiles,
            compDistanceKm: prevDistKm > 0 ? prevDistKm : nil,
            compRunCount: prevRuns.isEmpty ? nil : prevRuns.count,
            compAvgPaceSecPerKm: prevPaceSec,
            ytdDistanceKm: ytdKm
        )
    }

    private func yearStats(yearOffset: Int) -> SummaryPeriodStats {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date()) - yearOffset
        let acts = runWalkActivities.filter {
            cal.component(.year, from: $0.date) == year
        }

        let prevYear = year - 1
        let prevActs = runWalkActivities.filter {
            cal.component(.year, from: $0.date) == prevYear
        }
        let prevRuns = prevActs.filter { $0.type == .running }
        let prevDistKm = prevActs.reduce(0.0) { $0 + $1.distance / 1000 }
        let prevPaceSec: Double? = {
            let r = prevRuns.filter { $0.distance > 0 }
            guard !r.isEmpty else { return nil }
            let d = r.reduce(0.0) { $0 + $1.distance }
            let t = r.reduce(0.0) { $0 + $1.duration }
            return d > 0 ? t / (d / 1000) : nil
        }()

        return SummaryPeriodStats(
            kind: .yearly(year: year),
            activities: acts,
            useMiles: useMiles,
            compDistanceKm: prevDistKm > 0 ? prevDistKm : nil,
            compRunCount: prevRuns.isEmpty ? nil : prevRuns.count,
            compAvgPaceSecPerKm: prevPaceSec
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
        let s0 = periodStats(monthOffset: 0)
        let s1 = periodStats(monthOffset: 1)
        let s2 = periodStats(monthOffset: 2)
        let y0 = yearStats(yearOffset: 0)
        let y1 = yearStats(yearOffset: 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("기간별 결산")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            SummarySectionCard(stats: s0, manager: manager) { showShare0 = true }
                .padding(.horizontal, 16)
            SummarySectionCard(stats: s1, manager: manager) { showShare1 = true }
                .padding(.horizontal, 16)
            SummarySectionCard(stats: s2, manager: manager) { showShare2 = true }
                .padding(.horizontal, 16)
            SummarySectionCard(stats: y0, manager: manager) { showYearShare0 = true }
                .padding(.horizontal, 16)
            SummarySectionCard(stats: y1, manager: manager) { showYearShare1 = true }
                .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showShare0) {
            SummaryShareCardScreen(stats: s0, miniMeImage: miniMeStore.image)
        }
        .sheet(isPresented: $showShare1) {
            SummaryShareCardScreen(stats: s1, miniMeImage: miniMeStore.image)
        }
        .sheet(isPresented: $showShare2) {
            SummaryShareCardScreen(stats: s2, miniMeImage: miniMeStore.image)
        }
        .sheet(isPresented: $showYearShare0) {
            SummaryShareCardScreen(stats: y0, miniMeImage: miniMeStore.image)
        }
        .sheet(isPresented: $showYearShare1) {
            SummaryShareCardScreen(stats: y1, miniMeImage: miniMeStore.image)
        }
    }

    // MARK: - Shoes section

    @Environment(\.modelContext) private var modelContext

    private func cumulativeKm(for shoe: Shoe) -> Double {
        let sid = shoe.id.uuidString
        let workoutIDs = Set(allStories.lazy.filter { $0.shoeID == sid }.map { $0.workoutID })
        guard !workoutIDs.isEmpty else { return 0 }
        return manager.activities
            .lazy.filter { workoutIDs.contains($0.id.uuidString) }
            .reduce(0) { $0 + $1.distance } / 1000
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
                            Button {
                                shoeToDelete = shoe
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.red.opacity(0.6))
                                    .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
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
        .alert("신발 삭제", isPresented: .init(
            get: { shoeToDelete != nil },
            set: { if !$0 { shoeToDelete = nil } }
        )) {
            Button("삭제", role: .destructive) {
                if let shoe = shoeToDelete { modelContext.delete(shoe) }
                shoeToDelete = nil
            }
            Button("취소", role: .cancel) { shoeToDelete = nil }
        } message: {
            if let shoe = shoeToDelete {
                Text("'\(shoe.displayName)'을(를) 삭제하면 복구할 수 없어요.")
            }
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

private struct FormMetricsData {
    let cadence: Double?
    let prevCadence: Double?
    let power: Double?
    let prevPower: Double?
    let strideLength: Double?
    let prevStrideLength: Double?
    var hasAny: Bool { cadence != nil || power != nil || strideLength != nil }
}

private struct SummarySectionCard: View {
    let stats: SummaryPeriodStats
    let manager: HealthKitManager
    let onShare: () -> Void

    @State private var formMetrics: FormMetricsData? = nil

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
                            .foregroundStyle(.white)
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

                // Comparison strip
                if stats.compDistanceKm != nil {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        if let d = stats.distanceDeltaStr {
                            compChip(text: d, up: stats.distanceDeltaIsUp)
                        }
                        if let c = stats.runCountDeltaStr {
                            compChip(text: c, up: stats.runCount >= (stats.compRunCount ?? 0))
                        }
                        if let p = stats.paceDeltaStr {
                            compChip(text: p, up: p.contains("빨라짐"))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }

                // YTD
                if let ytd = stats.ytdStr {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.violet.opacity(0.7))
                        Text(ytd)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.violet.opacity(0.85))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }

                // Form metrics (워치 전용, 비동기 로드)
                if let fm = formMetrics, fm.hasAny {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    HStack(spacing: 0) {
                        if let cad = fm.cadence {
                            formMetricCell(value: "\(Int(cad.rounded()))spm",
                                           label: "케이던스",
                                           current: cad, prev: fm.prevCadence,
                                           higherBetter: true)
                        }
                        if let pwr = fm.power {
                            if fm.cadence != nil { formMetricDivider }
                            formMetricCell(value: "\(Int(pwr.rounded()))W",
                                           label: "파워",
                                           current: pwr, prev: fm.prevPower,
                                           higherBetter: true)
                        }
                        if let str = fm.strideLength {
                            if fm.cadence != nil || fm.power != nil { formMetricDivider }
                            formMetricCell(value: String(format: "%.2fm", str),
                                           label: "보폭",
                                           current: str, prev: fm.prevStrideLength,
                                           higherBetter: true)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
            }

            Spacer(minLength: 14)
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .task(id: stats.kind.title) {
            guard case .monthly(let y, let m) = stats.kind else { return }
            let cal = Calendar.current
            let start = cal.date(from: DateComponents(year: y, month: m)) ?? Date()
            let end   = cal.date(byAdding: .month, value: 1, to: start)  ?? Date()
            let prev  = cal.date(byAdding: .month, value: -1, to: start) ?? Date()

            async let cadFetch = manager.fetchMetricHistory(.cadence,      from: prev)
            async let pwrFetch = manager.fetchMetricHistory(.power,        from: prev)
            async let strFetch = manager.fetchMetricHistory(.strideLength, from: prev)
            let (cad, pwr, str) = await (cadFetch, pwrFetch, strFetch)

            func avg(_ pts: [(date: Date, value: Double)], from s: Date, to e: Date) -> Double? {
                let f = pts.filter { $0.date >= s && $0.date < e }
                guard !f.isEmpty else { return nil }
                return f.map(\.value).reduce(0, +) / Double(f.count)
            }

            formMetrics = FormMetricsData(
                cadence:          avg(cad, from: start, to: end),
                prevCadence:      avg(cad, from: prev,  to: start),
                power:            avg(pwr, from: start, to: end),
                prevPower:        avg(pwr, from: prev,  to: start),
                strideLength:     avg(str, from: start, to: end),
                prevStrideLength: avg(str, from: prev,  to: start)
            )
        }
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
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cellDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 0.5, height: 28)
            .padding(.horizontal, 10)
    }

    private func compChip(text: String, up: Bool) -> some View {
        let color: Color = up ? .green : Color(red: 1, green: 0.45, blue: 0.45)
        return Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func formMetricCell(value: String, label: String,
                                current: Double, prev: Double?,
                                higherBetter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(value)
                    .font(.system(size: 14, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let p = prev {
                    let up = current > p
                    let good = higherBetter ? up : !up
                    Image(systemName: up ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(good ? Color.green : Color(red: 1, green: 0.45, blue: 0.45))
                }
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(minWidth: 72, alignment: .leading)
    }

    private var formMetricDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 0.5, height: 32)
            .padding(.horizontal, 12)
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

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        field(label: "신발 이름", placeholder: "예: Nike Pegasus 41", text: $name)
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
                        let shoe = Shoe(name: name.trimmingCharacters(in: .whitespaces), brand: "")
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
