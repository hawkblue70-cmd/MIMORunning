import SwiftUI
import CloudKit

// MARK: - Store

@Observable final class MembersStore {
    var members: [CrewMember] = []
    var isLoading = false
    var errorMessage: String?

    @MainActor
    func load(crew: Crew) async {
        isLoading = true
        errorMessage = nil
        do {
            // 최신 kickedMemberIDs 반영을 위해 Crew 재조회
            let freshCrew = (try? await CrewManager.shared.findCrew(byCode: crew.code)) ?? crew
            members = try await CrewManager.shared.fetchRanking(crew: freshCrew)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - View

struct CrewMembersView: View {
    let crew: Crew
    let myID: String

    @State private var store = MembersStore()
    @State private var memberToKick: CrewMember?
    @State private var isKicking = false
    @State private var kickError: String?

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M.d"
        return f
    }()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if store.isLoading || isKicking {
                ProgressView().tint(Theme.violet)
            } else if let msg = store.errorMessage {
                errorView(message: msg)
            } else {
                content
            }
        }
        .navigationTitle(AppLanguage.shared.s("멤버 관리", "Manage Members"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(crew: crew) }
        .alert(
            AppLanguage.shared.s("멤버 내보내기", "Remove Member"),
            isPresented: Binding(
                get: { memberToKick != nil },
                set: { if !$0 { memberToKick = nil } }
            )
        ) {
            Button(AppLanguage.shared.s("내보내기", "Remove"), role: .destructive) {
                if let m = memberToKick { Task { await kickAndReload(member: m) } }
            }
            Button(AppLanguage.shared.s("취소", "Cancel"), role: .cancel) { memberToKick = nil }
        } message: {
            if let m = memberToKick {
                Text(AppLanguage.shared.s(
                    "\(m.nickname)님을 크루에서 내보낼까요?",
                    "Remove \(m.nickname) from the crew?"
                ))
            }
        }
        .alert(AppLanguage.shared.s("오류", "Error"), isPresented: Binding(
            get: { kickError != nil },
            set: { if !$0 { kickError = nil } }
        )) {
            Button("OK", role: .cancel) { kickError = nil }
        } message: {
            if let e = kickError { Text(e) }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(store.members.enumerated()), id: \.element.recordID) { index, member in
                    memberRow(member: member)
                    if index < store.members.count - 1 {
                        Divider().background(Color.white.opacity(0.07))
                    }
                }
            }
            .background(Color(hex: "1C1C22").opacity(1.0))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Member row

    private func memberRow(member: CrewMember) -> some View {
        let isMe = member.icloudID == myID
        let isOwner = crew.ownerID == member.icloudID

        return HStack(spacing: 12) {
            // 닉네임 + 배지 + 가입 정보
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(member.nickname)
                        .font(.system(size: 15, weight: isMe ? .bold : .regular))
                        .foregroundStyle(isMe ? Theme.violet : .white)
                    if isOwner {
                        Text(AppLanguage.shared.s("방장", "Owner"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.violet)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Theme.violet.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 5) {
                    Text(member.periodDistance > 0
                         ? String(format: "%.1f km", member.periodDistance)
                         : "—")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.3))
                    Text(AppLanguage.shared.s(
                        "가입 \(Self.dateFmt.string(from: member.joinedAt))",
                        "Joined \(Self.dateFmt.string(from: member.joinedAt))"
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // 내보내기 버튼 (본인 제외)
            if !isMe {
                Button {
                    memberToKick = member
                } label: {
                    Text(AppLanguage.shared.s("내보내기", "Remove"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.red.opacity(0.80))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(hex: "1C1C22").opacity(1.0))
    }

    // MARK: - Kick

    @MainActor
    private func kickAndReload(member: CrewMember) async {
        isKicking = true
        memberToKick = nil
        do {
            try await CrewManager.shared.kickMember(member, fromCrew: crew)
            await store.load(crew: crew)
        } catch {
            kickError = error.localizedDescription
        }
        isKicking = false
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
                Task { await store.load(crew: crew) }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.violet)
        }
    }
}
