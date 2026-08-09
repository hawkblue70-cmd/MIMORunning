import SwiftUI
import CloudKit

// MARK: - Store

@Observable final class CrewTabStore {
    var entries: [(crew: Crew, memberCount: Int)] = []
    var isLoading = false
    var errorMessage: String?

    @MainActor
    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            entries = try await CrewManager.shared.fetchMyCrews()
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
}

// MARK: - View

struct CrewTabView: View {
    let manager: HealthKitManager
    @Environment(CrewNicknameManager.self) private var nicknameManager
    @State private var store = CrewTabStore()
    @State private var showCreate = false
    @State private var showJoin = false

    private var atMax: Bool { store.entries.count >= 3 }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                content
            }
            .navigationTitle(AppLanguage.shared.s("크루", "Crew"))
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Crew.self) { crew in
                CrewRankingView(crew: crew, activities: manager.activities)
            }
        }
        .task { await store.load() }
        .sheet(isPresented: $showCreate) {
            CreateCrewView()
                .environment(nicknameManager)
                .onDisappear { Task { await store.load() } }
        }
        .sheet(isPresented: $showJoin) {
            JoinCrewView()
                .environment(nicknameManager)
                .onDisappear { Task { await store.load() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading {
            ProgressView().tint(Theme.violet)
        } else if let msg = store.errorMessage {
            errorView(message: msg)
        } else if store.entries.isEmpty {
            emptyView
        } else {
            crewList
        }
    }

    // MARK: - Empty state

    private var emptyView: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.violet.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.violet)
            }
            VStack(spacing: 8) {
                Text(AppLanguage.shared.s("아직 크루가 없어요", "No crews yet"))
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text(AppLanguage.shared.s("친구와 함께 달려보세요", "Run together with friends"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                Button { showCreate = true } label: {
                    Label(
                        AppLanguage.shared.s("크루 만들기", "Create Crew"),
                        systemImage: "plus.circle.fill"
                    )
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button { showJoin = true } label: {
                    Label(
                        AppLanguage.shared.s("코드로 참여", "Join with Code"),
                        systemImage: "person.badge.plus"
                    )
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.violet)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.violet.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Crew list

    private var crewList: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(store.entries, id: \.crew.code) { entry in
                        NavigationLink(value: entry.crew) {
                            crewCard(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
        }
        .overlay(alignment: .bottom) {
            bottomBar
        }
    }

    private func crewCard(entry: (crew: Crew, memberCount: Int)) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.crew.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                HStack(spacing: 5) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(AppLanguage.shared.s("\(entry.memberCount)명", "\(entry.memberCount) members"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            cycleBadge(cycle: entry.crew.resetCycle)
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func cycleBadge(cycle: String) -> some View {
        let label = cycle == "weekly"
            ? AppLanguage.shared.s("주간", "Weekly")
            : AppLanguage.shared.s("월간", "Monthly")
        return Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.violet)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Theme.violet.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if atMax {
                Text(AppLanguage.shared.s(
                    "크루는 최대 3개까지 참여할 수 있어요",
                    "You can join up to 3 crews"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button { showCreate = true } label: {
                    Label(AppLanguage.shared.s("만들기", "Create"), systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(atMax ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.white))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(atMax ? Color.gray.opacity(0.2) : Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(atMax)
                .buttonStyle(.plain)

                Button { showJoin = true } label: {
                    Label(AppLanguage.shared.s("코드 참여", "Join Code"), systemImage: "person.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(atMax ? .secondary : Theme.violet)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(atMax ? Color.gray.opacity(0.2) : Theme.violet.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(atMax)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Error state

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(AppLanguage.shared.s("다시 시도", "Retry")) {
                Task { await store.load() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.violet)
        }
    }
}
