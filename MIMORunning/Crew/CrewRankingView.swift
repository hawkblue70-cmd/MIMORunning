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
            try await CrewManager.shared.updateMyDistance(crewCode: crew.code, distanceKm: km)
            members = try await CrewManager.shared.fetchRanking(crewCode: crew.code)
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
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showDisbandConfirm = false
    @State private var showLeaveConfirm = false
    @State private var memberToKick: CrewMember?
    @State private var showKickConfirm = false
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

    private var myMember: CrewMember? {
        store.members.first { $0.icloudID == store.myID }
    }

    private var iAmRanked: Bool {
        (myMember?.periodDistance ?? 0) > 0
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
            Button(AppLanguage.shared.s("방 이름 변경", "Rename Crew")) {
                renameText = crew.name
                showRenameAlert = true
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
            Text(AppLanguage.shared.s("크루에서 나가시겠어요?", "Leave this crew?"))
        }
        // 멤버 강퇴 확인
        .alert(
            AppLanguage.shared.s("멤버 내보내기", "Remove Member"),
            isPresented: $showKickConfirm
        ) {
            Button(AppLanguage.shared.s("취소", "Cancel"), role: .cancel) { memberToKick = nil }
            Button(AppLanguage.shared.s("내보내기", "Remove"), role: .destructive) {
                guard let m = memberToKick else { return }
                Task { await doKick(m) }
            }
        } message: {
            if let m = memberToKick {
                Text(AppLanguage.shared.s(
                    "\(m.nickname)을(를) 크루에서 내보낼까요?",
                    "Remove \(m.nickname) from the crew?"
                ))
            }
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
                if rankedMembers.isEmpty {
                    emptyState
                } else {
                    rankingList
                }
                if !iAmRanked {
                    notYetNotice
                }
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

    // MARK: - Ranking list

    private var rankingList: some View {
        VStack(spacing: 0) {
            ForEach(Array(rankedMembers.enumerated()), id: \.element.recordID) { index, member in
                rankRow(rank: index + 1, member: member)
                if index < rankedMembers.count - 1 {
                    Divider().background(Color.white.opacity(0.06))
                }
            }
        }
        .background(Color(hex: "1C1C22").opacity(1.0))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func rankRow(rank: Int, member: CrewMember) -> some View {
        let isMe = member.icloudID == store.myID
        let canKick = store.isOwner && !isMe

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
        .contextMenu {
            if canKick {
                Button(role: .destructive) {
                    memberToKick = member
                    showKickConfirm = true
                } label: {
                    Label(
                        AppLanguage.shared.s("내보내기", "Remove"),
                        systemImage: "person.fill.xmark"
                    )
                }
            }
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.00, green: 0.84, blue: 0.00)
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return .secondary
        }
    }

    // MARK: - Empty / notice states

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 44))
                .foregroundStyle(Theme.violet.opacity(0.4))
            Text(AppLanguage.shared.s(
                "아직 아무도 안 뛰었어요\n첫 주자가 되어보세요!",
                "No one has run yet\nBe the first!"
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }

    private var notYetNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text(crew.resetCycle == "weekly"
                 ? AppLanguage.shared.s(
                    "이번 주 첫 러닝을 하면 순위에 올라요",
                    "Run this week to appear on the leaderboard"
                 )
                 : AppLanguage.shared.s(
                    "이번 달 첫 러닝을 하면 순위에 올라요",
                    "Run this month to appear on the leaderboard"
                 ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "1C1C22").opacity(1.0))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

    private func doLeave() async {
        isWorking = true
        do {
            try await CrewManager.shared.leaveCrew(crewCode: crew.code)
            onCrewDataChanged()
            dismiss()
        } catch {
            opError = error.localizedDescription
            isWorking = false
        }
    }

    private func doKick(_ member: CrewMember) async {
        isWorking = true
        memberToKick = nil
        do {
            try await CrewManager.shared.kickMember(member)
            store.members.removeAll { $0.recordID == member.recordID }
            onCrewDataChanged()
        } catch {
            opError = error.localizedDescription
        }
        isWorking = false
    }
}
