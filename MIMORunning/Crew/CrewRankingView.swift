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

            // findCrew와 fetchRanking을 병렬로 실행 (순차 → 동시)
            async let freshCrewFetch = CrewManager.shared.findCrew(byCode: crew.code)
            async let rankingFetch   = CrewManager.shared.fetchRanking(crew: crew)

            let freshCrew = (try? await freshCrewFetch) ?? crew
            var fetched   = try await rankingFetch

            // freshCrew의 최신 kickedMemberIDs로 재필터링·재정렬
            if !freshCrew.kickedMemberIDs.isEmpty {
                fetched = fetched
                    .filter { !freshCrew.kickedMemberIDs.contains($0.icloudID) }
                    .sorted { $0.periodDistance > $1.periodDistance }
            }

            members  = fetched
            isOwner  = freshCrew.ownerID == myID
            isLoading = false   // 데이터 표시 후 로딩 해제

            // 내 거리 계산 및 낙관적 UI 즉시 반영
            guard !activities.isEmpty else { return }
            let km     = Self.periodDistanceKm(crew: freshCrew, activities: activities)
            let lastKm = Self.lastPeriodDistanceKm(crew: freshCrew, activities: activities)

            if let idx = members.firstIndex(where: { $0.icloudID == myID }) {
                members[idx].periodDistance     = km
                members[idx].lastPeriodDistance = lastKm
                members.sort { $0.periodDistance > $1.periodDistance }
            }

            // CloudKit 저장은 백그라운드 (화면 차단 안 함)
            Task {
                try? await CrewManager.shared.updateMyDistance(
                    crewCode: freshCrew.code, distanceKm: km, lastDistanceKm: lastKm
                )
            }
            #if DEBUG
            print("[Ranking] code=\(crew.code) activities=\(activities.count) km=\(km) members=\(members.count)")
            #endif
        } catch let ckError as CKError {
            switch ckError.code {
            case .notAuthenticated:
                errorMessage = AppLanguage.shared.s("iCloud 로그인이 필요해요.", "iCloud sign-in required.")
            case .networkUnavailable, .networkFailure:
                errorMessage = AppLanguage.shared.s("네트워크 연결을 확인해 주세요.", "Check your network connection.")
            default:
                errorMessage = ckError.localizedDescription
            }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// 크루 생성일 기준으로 N일 주기의 현재 기간을 계산해 러닝 거리를 반환.
    static func periodDistanceKm(crew: Crew, activities: [Activity]) -> Double {
        let (start, end) = currentPeriod(crew: crew)
        return activities
            .filter { $0.type == .running && $0.date >= start && $0.date < end }
            .reduce(0) { $0 + $1.distance / 1000 }
    }

    /// 직전 기간(현재 기간 시작 - N일 ~ 현재 기간 시작)의 러닝 거리를 반환.
    /// 첫 번째 기간이라 직전이 없으면 0 반환.
    static func lastPeriodDistanceKm(crew: Crew, activities: [Activity]) -> Double {
        let intervalDays = max(1, Int(crew.resetCycle) ?? 30)
        let interval = TimeInterval(intervalDays * 24 * 3600)
        let (currentStart, _) = currentPeriod(crew: crew)
        let lastStart = currentStart.addingTimeInterval(-interval)
        guard lastStart >= crew.createdAt else { return 0 }
        return activities
            .filter { $0.type == .running && $0.date >= lastStart && $0.date < currentStart }
            .reduce(0) { $0 + $1.distance / 1000 }
    }

    /// 생성일로부터 N일 단위로 현재 기간의 시작·끝을 반환.
    static func currentPeriod(crew: Crew) -> (start: Date, end: Date) {
        let intervalDays = max(1, Int(crew.resetCycle) ?? 30)
        let interval = TimeInterval(intervalDays * 24 * 3600)
        let now = Date()
        let elapsed = now.timeIntervalSince(crew.createdAt)
        let periodIndex = elapsed >= 0 ? floor(elapsed / interval) : 0
        let start = crew.createdAt.addingTimeInterval(periodIndex * interval)
        let end   = start.addingTimeInterval(interval)
        return (start, end)
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
    @State private var codeCopied = false
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
                inviteCodeRow
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
            Text(AppLanguage.shared.s(
                "\(Int(crew.resetCycle) ?? 30)일 주기",
                "\(Int(crew.resetCycle) ?? 30)d cycle"
            ))
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
        let (start, end) = RankingStore.currentPeriod(crew: crew)
        let fmt = DateFormatter(); fmt.dateFormat = "M.d"
        // end는 다음 기간 시작이므로 1초 빼서 마지막 날 표시
        let displayEnd = end.addingTimeInterval(-1)
        return "\(fmt.string(from: start)) ~ \(fmt.string(from: displayEnd))"
    }

    // MARK: - Invite code row

    private var inviteCodeRow: some View {
        HStack(spacing: 12) {
            Text(AppLanguage.shared.s("초대 코드", "Invite code"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(crew.code)
                .font(.system(size: 18, weight: .black, design: .monospaced))
                .foregroundStyle(Theme.violet)
                .tracking(4)
            Button {
                UIPasteboard.general.string = crew.code
                codeCopied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    codeCopied = false
                }
            } label: {
                Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14))
                    .foregroundStyle(codeCopied ? Color.green : Theme.violet)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(hex: "1C1C22").opacity(1.0))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f km", member.periodDistance))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isMe ? Theme.violet : .white)
                if member.lastPeriodDistance > 0 {
                    Text(String(format: AppLanguage.shared.s("지난 %.1f", "prev %.1f"), member.lastPeriodDistance))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(white: 0.40))
                } else {
                    Text(AppLanguage.shared.s("지난 —", "prev —"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.28))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
