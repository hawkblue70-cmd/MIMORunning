import SwiftUI
import CloudKit

// MARK: - Store

@Observable final class RankingStore {
    var members: [CrewMember] = []
    var myID: String = ""
    var isOwner: Bool = false
    var isLoading = false
    var errorMessage: String?

    @MainActor
    func load(crew: Crew, activities: [Activity]) async {
        isLoading = true
        errorMessage = nil
        do {
            myID = try await CrewManager.shared.userRecordID()
            isOwner = crew.ownerID == myID
            let km = Self.periodDistanceKm(cycle: crew.resetCycle, activities: activities)
            // activities가 빈 배열(HealthKit 로드 전)이면 0km으로 덮어쓰지 않는다.
            if !activities.isEmpty {
                try await CrewManager.shared.updateMyDistance(crewCode: crew.code, distanceKm: km)
            }
            let fetched = try await CrewManager.shared.fetchRanking(crewCode: crew.code)
            #if DEBUG
            print("[Ranking] code=\(crew.code) activities=\(activities.count) km=\(km) fetched=\(fetched.count): \(fetched.map { "\($0.nickname)/\($0.periodDistance)km" })")
            #endif
            members = fetched
        } catch let ckError as CKError {
            switch ckError.code {
            case .notAuthenticated:
                errorMessage = AppLanguage.shared.s("iCloud 로그인이 필요해요.", "iCloud sign-in required.")
            case .networkUnavailable, .networkFailure:
                errorMessage = AppLanguage.shared.s("네트워크 연결을 확인해 주세요.", "Check your network connection.")
            default:
                errorMessage = ckError.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private static var mondayCal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = Locale.current
        return c
    }()

    static func periodDistanceKm(cycle: String, activities: [Activity]) -> Double {
        let cal = mondayCal
        let now = Date()
        let runs = activities.filter { $0.type == .running }
        if cycle == "weekly" {
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            return runs
                .filter { cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0.date) == comps }
                .reduce(0) { $0 + $1.distance / 1000 }
        } else {
            guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return 0 }
            return runs
                .filter { $0.date >= monthStart }
                .reduce(0) { $0 + $1.distance / 1000 }
        }
    }
}

// MARK: - View

struct CrewRankingView: View {
    @State private var crew: Crew
    let activities: [Activity]
    let onCrewDataChanged: () -> Void

    @State private var store = RankingStore()
    @Environment(\.dismiss) private var dismiss

    // Dialog / alert state
    @State private var showManageSheet = false
    @State private var showMembersView = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showDisbandConfirm = false
    @State private var showLeaveConfirm = false
    @State private var opError: String?
    @State private var isWorking = false

    init(crew: Crew, activities: [Activity], onCrewDataChanged: @escaping () -> Void = {}) {
        _crew = State(initialValue: crew)
        self.activities = activities
        self.onCrewDataChanged = onCrewDataChanged
    }

    private var rankedMembers: [CrewMember] {
        store.members.filter { $0.periodDistance > 0 }
    }

    private var unrankedMembers: [CrewMember] {
        store.members.filter { $0.periodDistance == 0 }
    }

    private var myMember: CrewMember? {
        store.members.first { $0.icloudID == store.myID }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if store.isLoading {
                ProgressView().tint(Theme.violet)
            } else if let msg = store.errorMessage {
                errorView(message: msg)
            } else {
                content
            }
            if isWorking {
                Color.black.opacity(0.35).ignoresSafeArea()
                ProgressView().tint(Theme.violet)
            }
        }
        .navigationTitle(crew.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await store.load(crew: crew, activities: activities) }
        // 방장 관리 액션시트
        .confirmationDialog(
            AppLanguage.shared.s("관리", "Manage"),
            isPresented: $showManageSheet,
            titleVisibility: .visible
        ) {
            Button(AppLanguage.shared.s("멤버 관리", "Manage Members")) {
                showMembersView = true
            }
            Button(AppLanguage.shared.s("방 이름 변경", "Rename Crew")) {
                renameText = crew.name
                showRenameAlert = true
            }
            Button(AppLanguage.shared.s("크루 나가기", "Leave Crew"), role: .destructive) {
                showLeaveConfirm = true
            }
            Button(AppLanguage.shared.s("크루 해체", "Disband Crew"), role: .destructive) {
                showDisbandConfirm = true
            }
            Button(AppLanguage.shared.s("취소", "Cancel"), role: .cancel) {}
        }
        // 이름 변경 알럿
        .alert(AppLanguage.shared.s("방 이름 변경", "Rename Crew"), isPresented: $showRenameAlert) {
            TextField(AppLanguage.shared.s("크루 이름", "Crew name"), text: $renameText)
            Button(AppLanguage.shared.s("취소", "Cancel"), role: .cancel) {}
            Button(AppLanguage.shared.s("변경", "Rename")) {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                guard (2...20).contains(trimmed.count) else { return }
                Task { await doRename(newName: trimmed) }
            }
        } message: {
            Text(AppLanguage.shared.s("2~20자로 입력해 주세요", "Enter 2–20 characters"))
        }
        // 크루 해체 확인
        .confirmationDialog(
            AppLanguage.shared.s("크루 해체", "Disband Crew"),
            isPresented: $showDisbandConfirm,
            titleVisibility: .visible
        ) {
            Button(AppLanguage.shared.s("해체", "Disband"), role: .destructive) {
                Task { await doDisband() }
            }
            Button(AppLanguage.shared.s("취소", "Cancel"), role: .cancel) {}
        } message: {
            Text(AppLanguage.shared.s(
                "정말 해체할까요? 모든 기록이 사라지고 되돌릴 수 없어요.",
                "Are you sure? All data will be lost and cannot be undone."
            ))
        }
        // 크루 나가기 확인
        .confirmationDialog(
            AppLanguage.shared.s("크루 나가기", "Leave Crew"),
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button(AppLanguage.shared.s("나가기", "Leave"), role: .destructive) {
                Task { await doLeave() }
            }
            Button(AppLanguage.shared.s("취소", "Cancel"), role: .cancel) {}
        } message: {
            Text(leaveConfirmMessage)
        }
        // 작업 오류 알럿
        .alert(AppLanguage.shared.s("오류", "Error"), isPresented: Binding(
            get: { opError != nil },
            set: { if !$0 { opError = nil } }
        )) {
            Button(AppLanguage.shared.s("확인", "OK"), role: .cancel) { opError = nil }
        } message: {
            if let e = opError { Text(e) }
        }
        // 멤버 관리 시트
        .sheet(isPresented: $showMembersView, onDismiss: {
            Task { await store.load(crew: crew, activities: activities) }
        }) {
            NavigationStack {
                CrewMembersView(crew: crew, myID: store.myID)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if !store.isLoading {
                if store.isOwner {
                    Button { showManageSheet = true } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Theme.violet)
                    }
                } else {
                    Button {
                        showLeaveConfirm = true
                    } label: {
                        Text(AppLanguage.shared.s("나가기", "Leave"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                periodHeader
                rankingCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Period header

    private var periodHeader: some View {
        HStack(spacing: 10) {
            Text(crew.resetCycle == "weekly"
                 ? AppLanguage.shared.s("주간", "Weekly")
                 : AppLanguage.shared.s("월간", "Monthly"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.violet)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.violet.opacity(0.15))
                .clipShape(Capsule())

            Text(periodDateString)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(14)
        .background(Color(hex: "1C1C22").opacity(1.0))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var periodDateString: String {
        if crew.resetCycle == "weekly" {
            var cal = Calendar(identifier: .gregorian)
            cal.firstWeekday = 2
            let now = Date()
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            guard let weekStart = cal.date(from: comps),
                  let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) else {
                return AppLanguage.shared.s("이번 주", "This week")
            }
            let fmt = DateFormatter(); fmt.dateFormat = "M.d"
            return "\(fmt.string(from: weekStart)) ~ \(fmt.string(from: weekEnd))"
        } else {
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy.M"
            return fmt.string(from: Date())
        }
    }

    // MARK: - Combined ranking card (뛴 사람 + 안 뛴 사람)

    private var rankingCard: some View {
        VStack(spacing: 0) {
            // 뛴 사람 섹션
            if rankedMembers.isEmpty {
                noRunYetHeader
            } else {
                ForEach(Array(rankedMembers.enumerated()), id: \.element.recordID) { index, member in
                    rankRow(rank: index + 1, member: member)
                    if index < rankedMembers.count - 1 {
                        Divider().background(Color.white.opacity(0.06))
                    }
                }
            }
            // 안 뛴 사람 섹션 (0km)
            if !unrankedMembers.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                ForEach(unrankedMembers, id: \.recordID) { member in
                    unrankedRow(member: member)
                }
            }
        }
        .background(Color(hex: "1C1C22").opacity(1.0))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // 전원 0km일 때 카드 상단 헤더
    private var noRunYetHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 18))
                .foregroundStyle(Theme.violet.opacity(0.4))
            Text(AppLanguage.shared.s("아직 아무도 안 뛰었어요", "No one has run yet"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func rankRow(rank: Int, member: CrewMember) -> some View {
        let isMe = member.icloudID == store.myID

        return HStack(spacing: 14) {
            ZStack {
                if rank <= 3 {
                    Circle()
                        .fill(rankColor(rank).opacity(0.15))
                        .frame(width: 32, height: 32)
                }
                Text("\(rank)")
                    .font(.system(size: 14, weight: rank <= 3 ? .black : .semibold))
                    .foregroundStyle(rank <= 3 ? rankColor(rank) : Color.secondary)
                    .frame(width: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.nickname)
                        .font(.system(size: 15, weight: isMe ? .bold : .regular))
                        .foregroundStyle(isMe ? Theme.violet : .white)
                    if isMe {
                        Text(AppLanguage.shared.s("나", "me"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.violet)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Theme.violet.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            Text(String(format: "%.1f km", member.periodDistance))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(isMe ? Theme.violet : .white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            Color(hex: "1C1C22").opacity(1.0)
            if isMe { Theme.violet.opacity(0.08) }
        }
    }

    // MARK: - Unranked row (0km, 흐리게)

    @ViewBuilder
    private func unrankedRow(member: CrewMember) -> some View {
        let isMe = member.icloudID == store.myID
        HStack(spacing: 14) {
            Color.clear.frame(width: 32, height: 32)
            HStack(spacing: 6) {
                Text(member.nickname)
                    .font(.system(size: 15))
                    .foregroundStyle(isMe ? Theme.violet.opacity(0.55) : Color(white: 0.42))
                if isMe {
                    Text(AppLanguage.shared.s("나", "me"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.violet.opacity(0.45))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.violet.opacity(0.07))
                        .clipShape(Capsule())
                }
            }
            Spacer()
            Text(AppLanguage.shared.s("아직", "—"))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.32))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "1C1C22").opacity(1.0))
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.00, green: 0.84, blue: 0.00)
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return .secondary
        }
    }

    // MARK: - Error state

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(AppLanguage.shared.s("다시 시도", "Retry")) {
                Task { await store.load(crew: crew, activities: activities) }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.violet)
        }
    }

    // MARK: - Operations

    private func doRename(newName: String) async {
        isWorking = true
        do {
            crew = try await CrewManager.shared.renameCrew(crew: crew, newName: newName)
            onCrewDataChanged()
        } catch {
            opError = error.localizedDescription
        }
        isWorking = false
    }

    private func doDisband() async {
        isWorking = true
        do {
            try await CrewManager.shared.disbandCrew(crew: crew)
            onCrewDataChanged()
            dismiss()
        } catch {
            opError = error.localizedDescription
            isWorking = false
        }
    }

    private var leaveConfirmMessage: String {
        guard store.isOwner else {
            return AppLanguage.shared.s("크루에서 나가시겠어요?", "Leave this crew?")
        }
        let hasOthers = store.members.contains { $0.icloudID != store.myID }
        if hasOthers {
            return AppLanguage.shared.s(
                "나가면 다음 분에게 방장이 넘어가요.",
                "Ownership will transfer to the next member."
            )
        } else {
            return AppLanguage.shared.s(
                "나가면 크루가 사라져요.",
                "Leaving will disband the crew."
            )
        }
    }

    private func doLeave() async {
        isWorking = true
        do {
            try await CrewManager.shared.leaveCrew(crew: crew)
            onCrewDataChanged()
            dismiss()
        } catch {
            opError = error.localizedDescription
            isWorking = false
        }
    }

}
