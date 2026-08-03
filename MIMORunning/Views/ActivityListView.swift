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

// MARK: - List item model

private enum ListItem: Identifiable {
    case workout(Activity)
    case restDay(date: Date, entry: OneLinerEntry, isDiary: Bool)

    var id: String {
        switch self {
        case .workout(let a):        return a.id.uuidString
        case .restDay(let d, _, _):  return "restday-\(Int(d.timeIntervalSince1970))"
        }
    }
    var date: Date {
        switch self {
        case .workout(let a):       return a.date
        case .restDay(let d, _, _): return d
        }
    }
}

// 날짜 기반 카드 제목 — 교체 시 이 한 곳만 수정
private enum OneLinerListLabels {
    static var diary:   String { AppLanguage.shared.s("일기",   "Diary") }
    static var restDay: String { AppLanguage.shared.s("쉬는 날", "Rest Day") }
}

// MARK: - Activity List

private struct ActivityListContent: View {
    var manager: HealthKitManager
    @EnvironmentObject private var engine: MREngineStore
    @Environment(RaceDetector.self) private var raceDetector
    @Environment(\.modelContext) private var modelContext
    private let pro = ProManager.shared
    @State private var displayCount = 50
    @State private var showPaywall = false
    @State private var restDaySheetDate: Date? = nil
    @AppStorage("showRunning")  private var showRunning  = true
    @AppStorage("showWalking")  private var showWalking  = false
    @AppStorage("showHiking")   private var showHiking   = false

    @Query private var stories: [WorkoutStory]
    @Query private var shoes: [Shoe]
    @Query private var allOneLinerEntries: [OneLinerEntry]

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

    private var visibleActivities: [Activity] { Array(filteredActivities.prefix(displayCount)) }

    private func deleteRestDayEntries(for date: Date) {
        let wid = OneLinerEntry.restDayWorkoutID(for: date)
        allOneLinerEntries
            .filter { $0.workoutID == wid }
            .forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    /// True when today has no recorded workout (running, walking, or hiking).
    private var isTodayRestDay: Bool {
        !manager.activities.contains { Calendar.current.isDateInToday($0.date) }
    }

    /// True when the given date has at least one recorded workout.
    private func hasWorkout(on date: Date) -> Bool {
        manager.activities.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    private var todayRestDayEntry: OneLinerEntry? {
        let wid = OneLinerEntry.restDayWorkoutID(for: Date())
        let candidates = allOneLinerEntries.filter { $0.workoutID == wid }
        // Prefer videotexts (v4recipes) over gradient (nil) for accurate preview
        return candidates.first(where: { $0.mediaRef == "videotexts" })
            ?? candidates.first(where: { $0.mediaRef == nil })
            ?? candidates.first
    }

    /// Past rest day entries (not today) that have content — one per date, best entry preferred.
    private var pastRestDayItems: [ListItem] {
        let todayWid = OneLinerEntry.restDayWorkoutID(for: Date())
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        var byWid: [String: [OneLinerEntry]] = [:]
        for e in allOneLinerEntries {
            guard e.workoutID.hasPrefix("date:"),
                  e.workoutID != todayWid,
                  e.hasContent else { continue }
            byWid[e.workoutID, default: []].append(e)
        }
        var result: [ListItem] = []
        for (wid, entries) in byWid {
            let best = entries.first(where: { $0.mediaRef == "videotexts" })
                ?? entries.first(where: { $0.mediaRef == nil })
                ?? entries[0]
            let dateStr = String(wid.dropFirst("date:".count))
            guard let date = fmt.date(from: dateStr) else { continue }
            result.append(.restDay(date: date, entry: best, isDiary: hasWorkout(on: date)))
        }
        return result
    }

    /// Paginated workouts merged with past rest days + today's diary — sorted newest first.
    private var mergedItems: [ListItem] {
        var items = visibleActivities.map { ListItem.workout($0) }
        items.append(contentsOf: pastRestDayItems)
        // 오늘 고아 방지: 워크아웃이 있는 날에도 일기 내용이 있으면 '일기' 카드로 추가.
        // pastRestDayItems는 오늘을 제외하므로 여기서 별도 처리.
        if !isTodayRestDay, let entry = todayRestDayEntry, entry.hasContent {
            items.append(.restDay(date: Date(), entry: entry, isDiary: true))
        }
        return items.sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if manager.isLoading && manager.activities.isEmpty {
                ProgressView().tint(Theme.violet)
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

                        if let rc = engine.raceDayCard, MRRaceDayView.shouldShow(rc) {
                            MRRaceDayView(card: rc)
                        }

                        MRTodayCardView()

                        if !pro.isPro {
                            TrialBannerView(
                                isExpired: pro.isTrialExpired,
                                daysRemaining: pro.daysRemainingInTrial
                            ) { showPaywall = true }
                        }

                        // 오늘 운동 기록이 없으면 쉬는 날 행 표시 (isDiary: false 고정 — 워크아웃 없는 날)
                        if isTodayRestDay && !manager.isLoading {
                            RestDayListRow(entry: todayRestDayEntry, date: Date(), isDiary: false) {
                                restDaySheetDate = Date()
                            }
                        }

                        if manager.activities.isEmpty {
                            EmptyActivitiesView()
                        } else if filteredActivities.isEmpty {
                            FilteredEmptyView()
                        } else {
                            ForEach(mergedItems) { item in
                                switch item {
                                case .workout(let activity):
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
                                case .restDay(let date, let entry, let isDiary):
                                    SwipeableRestDayRow(
                                        entry: entry, date: date, isDiary: isDiary,
                                        onTap: { restDaySheetDate = date },
                                        onDelete: { deleteRestDayEntries(for: date) }
                                    )
                                }
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .refreshable {
                    displayCount = 50
                    await manager.fetchActivities(forced: true)
                }
            }
        }
        .onChange(of: showRunning)  { _, _ in displayCount = 50 }
        .onChange(of: showWalking)  { _, _ in displayCount = 50 }
        .onChange(of: showHiking)   { _, _ in displayCount = 50 }
        .task {
            if let all = try? modelContext.fetch(FetchDescriptor<OneLinerEntry>()) {
                // ── stale 키("restDay-") 정리 ──
                let stale = all.filter { $0.workoutID.hasPrefix("restDay-") }
                if !stale.isEmpty {
                    stale.forEach { modelContext.delete($0) }
                    try? modelContext.save()
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            ProPaywallSheet()
        }
        .sheet(isPresented: Binding(
            get: { restDaySheetDate != nil },
            set: { if !$0 { restDaySheetDate = nil } }
        )) {
            if let d = restDaySheetDate {
                // .id(d): 날짜가 다르면 SwiftUI가 기존 뷰를 재사용하지 않고
                // 완전히 새 뷰를 생성 → @State 오염 방지
                RestDayOneLinerSheet(date: d).id(d)
            }
        }
    }
}

// MARK: - Swipeable Rest Day Row

private struct SwipeableRestDayRow: View {
    let entry:    OneLinerEntry?
    let date:     Date
    let isDiary:  Bool
    let onTap:    () -> Void
    let onDelete: () -> Void

    // @State(not @GestureState) — 손 떼는 순간 0 리셋 없음, overlay가 히트테스트 담당
    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    private let deleteWidth: CGFloat = 72

    var body: some View {
        RestDayListRow(entry: entry, date: date, isDiary: isDiary) {
            if offset != 0 {
                withAnimation(.spring(response: 0.22)) { offset = 0 }
            } else {
                onTap()
            }
        }
        .offset(x: offset)
        // overlay: 행의 원래 frame 기준 trailing에 붙음 — offset이 만든 빈 공간에 정확히 위치
        .overlay(alignment: .trailing) {
            if offset < -4 {
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.22)) { offset = 0 }
                    onDelete()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: max(0, -offset))
                        .frame(maxHeight: .infinity)
                        .background(
                            Color.red.clipShape(RoundedRectangle(cornerRadius: 10))
                        )
                        .clipped()
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    // 첫 이벤트(이동 작음)에서 시작 offset 캡처
                    if abs(v.translation.width) < 30 { dragStartOffset = offset }
                    offset = min(0, max(-deleteWidth, dragStartOffset + v.translation.width))
                }
                .onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        offset = offset < -deleteWidth / 3 ? -deleteWidth : 0
                    }
                }
        )
    }
}

// MARK: - Rest Day List Row

private struct RestDayListRow: View {
    let entry:   OneLinerEntry?
    let date:    Date
    let isDiary: Bool   // true = 워크아웃이 있는 날의 일기 카드
    let onTap:   () -> Void

    @State private var thumbnail: UIImage? = nil

    private var hasEntry:  Bool { (entry?.hasContent ?? false) || (entry?.hasMedia ?? false) }
    private var mediaInfo: OneLinerEntry.RestDayMediaInfo? { entry?.restDayMediaInfo }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 10) {
                // Left: type label row + text
                VStack(alignment: .leading, spacing: 6) {
                    // Top: 아이콘 + 제목(쉬는 날 / 일기) | date · time
                    HStack(alignment: .top) {
                        HStack(spacing: 4) {
                            Image(systemName: isDiary ? "pencil" : "moon.zzz.fill")
                                .foregroundStyle(isDiary ? Theme.violet.opacity(0.85) : Color(hex: "FFC74D"))
                            Text(isDiary ? OneLinerListLabels.diary : OneLinerListLabels.restDay)
                                .foregroundStyle(Color(hex: "6E6E78"))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        dateTimeLabel
                    }
                    // Text line
                    if hasEntry, let preview = entry?.previewText, !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    } else if !hasEntry {
                        Text(AppLanguage.shared.s("이야기 추가하기", "Add your story"))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.violet.opacity(0.8))
                    }
                }

                Spacer(minLength: 0)

                // Right: thumbnail + count badge (only when media exists)
                if let info = mediaInfo, info.clipCount > 0 {
                    thumbnailBadge(info)
                } else if !hasEntry {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "4E4E5A"))
                }
            }
            .padding(10)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                if !hasEntry {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(Color.white.opacity(0.18))
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: entry?.text) { thumbnail = loadThumbnail() }
    }

    // MARK: - Thumbnail badge (right side, 48pt)

    private func thumbnailBadge(_ info: OneLinerEntry.RestDayMediaInfo) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let img = thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.07)
                        .overlay {
                            Image(systemName: info.isSlide ? "photo.stack" : "photo")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            if info.clipCount > 1 {
                Text("\(info.clipCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.65))
                    .clipShape(Capsule())
                    .offset(x: 4, y: 4)
            }
        }
    }

    // MARK: - Date/time (running-card format)

    private var dateTimeLabel: some View {
        let displayTime = entry?.createdAt ?? date
        return HStack(spacing: 4) {
            Text(dateStr(date))
                .foregroundStyle(.white)
            Text(weekdayStr(date))
                .foregroundStyle(weekdayColor(date))
            if hasEntry {
                Text(timeStr(displayTime))
                    .foregroundStyle(.white)
            }
        }
        .font(.system(size: 13, weight: .medium))
    }

    // MARK: - Helpers

    private func loadThumbnail() -> UIImage? {
        guard let info = entry?.restDayMediaInfo else { return nil }
        if let pr = info.photoRef, !pr.isEmpty { return OneLinerPhotoStore.load(mediaRef: pr) }
        if let tr = info.thumbRef, !tr.isEmpty { return ClipThumbStore.load(ref: tr) }
        return nil
    }

    private func dateStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US"); f.dateFormat = "yyyy. M. d"
        return f.string(from: d)
    }
    private func weekdayStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "EEEEE"
        return f.string(from: d)
    }
    private func timeStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US"); f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
    private func weekdayColor(_ d: Date) -> Color {
        switch Calendar.current.component(.weekday, from: d) {
        case 1: return Theme.heartRate
        case 7: return Color(hex: "6699FF")
        default: return Color(hex: "FFC74D")
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

    private static let datePart: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "yyyy. M. d"
        return df
    }()
    private static let weekdayPart: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "EEEEE"  // 요일 한 글자: 월화수목금토일
        return df
    }()
    private static let timePart: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "h:mm a"
        return df
    }()

    private var formattedDatePart:    String { Self.datePart.string(from: activity.date) }
    private var formattedWeekday:     String { Self.weekdayPart.string(from: activity.date) }
    private var formattedTimePart:    String { Self.timePart.string(from: activity.date) }

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
                    HStack(spacing: 4) {
                        Text(formattedDatePart)
                            .foregroundStyle(.white)
                        Text(formattedWeekday)
                            .foregroundStyle(Color(hex: "FFC74D"))
                        Text(formattedTimePart)
                            .foregroundStyle(.white)
                    }
                    .font(.system(size: 13, weight: .medium))
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
                            .foregroundStyle(Color(red: 0.2, green: 1.0, blue: 0.4))
                        Text(shoe)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(red: 0.2, green: 1.0, blue: 0.4))
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

