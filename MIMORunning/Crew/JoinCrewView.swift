import SwiftUI
import CloudKit

struct JoinCrewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CrewNicknameManager.self) private var nicknameManager

    @State private var code = ""
    @State private var isLoading = false
    @State private var joinedCrewName: String?
    @State private var errorMessage: String?

    private var canJoin: Bool {
        code.count == 6 && nicknameManager.nickname != nil && !isLoading
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if let crewName = joinedCrewName {
                    successView(crewName: crewName)
                } else {
                    formView
                }
            }
            .navigationTitle(AppLanguage.shared.s("크루 참여", "Join Crew"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Form

    private var formView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if nicknameManager.nickname == nil {
                    nicknameRequiredBanner
                }

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLanguage.shared.s("초대 코드", "Invite code"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("A3K9F2", text: $code)
                            .font(.system(size: 28, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .keyboardType(.asciiCapable)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .tracking(6)
                            .onChange(of: code) { _, newValue in
                                code = String(
                                    newValue
                                        .uppercased()
                                        .filter { $0.isLetter || $0.isNumber }
                                        .prefix(6)
                                )
                            }
                            .disabled(isLoading)

                        Text(AppLanguage.shared.s(
                            "방장에게 받은 6자리 코드를 입력하세요",
                            "Enter the 6-character code from the crew owner"
                        ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Theme.heartRate)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                }

                Button {
                    Task { await doJoin() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text(AppLanguage.shared.s("참여하기", "Join"))
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canJoin ? Theme.violet : Color.gray.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canJoin)
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                Spacer(minLength: 40)
            }
            .padding(.top, 20)
        }
    }

    // MARK: - Success

    private func successView(crewName: String) -> some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.violet.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Theme.violet)
            }

            VStack(spacing: 8) {
                Text(AppLanguage.shared.s(
                    "\(crewName) 크루에 합류했어요!",
                    "You joined \(crewName)!"
                ))
                .font(.title2.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

                Text(AppLanguage.shared.s(
                    "크루 탭에서 멤버들의 기록을 확인할 수 있어요",
                    "Check your crew's records in the Crew tab"
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button(AppLanguage.shared.s("확인", "Done")) { dismiss() }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.violet)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Nickname required banner

    private var nicknameRequiredBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 22))
                .foregroundStyle(Theme.violet)
            VStack(alignment: .leading, spacing: 3) {
                Text(AppLanguage.shared.s("닉네임이 필요해요", "Nickname required"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text(AppLanguage.shared.s(
                    "나 탭에서 크루 닉네임을 먼저 설정해 주세요",
                    "Set your crew nickname in the Me tab first"
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
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

    // MARK: - Action

    @MainActor
    private func doJoin() async {
        guard canJoin, let nickname = nicknameManager.nickname else { return }
        isLoading = true
        errorMessage = nil
        do {
            let crewName = try await CrewManager.shared.joinCrew(code: code, nickname: nickname)
            joinedCrewName = crewName
        } catch let crewError as CrewError {
            errorMessage = crewError.localizedDescription
        } catch let ckError as CKError {
            switch ckError.code {
            case .notAuthenticated:
                errorMessage = AppLanguage.shared.s(
                    "iCloud 로그인이 필요해요.",
                    "iCloud sign-in required."
                )
            case .networkUnavailable, .networkFailure:
                errorMessage = AppLanguage.shared.s(
                    "네트워크 연결을 확인해 주세요.",
                    "Check your network connection."
                )
            default:
                errorMessage = ckError.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
