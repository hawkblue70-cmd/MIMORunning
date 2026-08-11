import SwiftUI
import CloudKit

struct CreateCrewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CrewNicknameManager.self) private var nicknameManager

    @State private var crewName = ""
    @State private var resetCycle = "30"
    @State private var isLoading = false
    @State private var createdCrew: Crew?
    @State private var errorMessage: String?
    @State private var codeCopied = false

    private var isNameValid: Bool {
        let t = crewName.trimmingCharacters(in: .whitespaces)
        return t.count >= 2 && t.count <= 20
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if let crew = createdCrew {
                    successView(crew: crew)
                } else {
                    formView
                }
            }
            .navigationTitle(AppLanguage.shared.s("크루 만들기", "Create Crew"))
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
                    // 방 이름
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLanguage.shared.s("방 이름", "Crew name"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(
                            AppLanguage.shared.s("우리 크루 이름 (2~20자)", "Name (2–20 chars)"),
                            text: $crewName
                        )
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .autocorrectionDisabled()
                        .disabled(isLoading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)

                    rowDivider

                    // 리셋 주기
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(AppLanguage.shared.s("리셋 주기", "Reset cycle"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(AppLanguage.shared.s("생성 후 변경할 수 없어요", "Cannot be changed after creation"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $resetCycle) {
                            Text("5일").tag("5")
                            Text("10일").tag("10")
                            Text("20일").tag("20")
                            Text("30일").tag("30")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                        .disabled(isLoading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
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
                    Task { await doCreate() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text(AppLanguage.shared.s("만들기", "Create"))
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canCreate ? Theme.violet : Color.gray.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canCreate)
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                Spacer(minLength: 40)
            }
            .padding(.top, 20)
        }
    }

    private var canCreate: Bool {
        isNameValid && nicknameManager.nickname != nil && !isLoading
    }

    // MARK: - Success

    private func successView(crew: Crew) -> some View {
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
                Text(AppLanguage.shared.s("크루가 만들어졌어요!", "Crew created!"))
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text(crew.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // 코드 카드
            VStack(spacing: 10) {
                Text(AppLanguage.shared.s("초대 코드", "Invite code"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(crew.code)
                    .font(.system(size: 44, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.violet)
                    .tracking(8)

                Button {
                    UIPasteboard.general.string = crew.code
                    codeCopied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        codeCopied = false
                    }
                } label: {
                    Label(
                        codeCopied
                            ? AppLanguage.shared.s("복사됨 ✓", "Copied ✓")
                            : AppLanguage.shared.s("코드 복사", "Copy code"),
                        systemImage: codeCopied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(codeCopied ? Color.green : Theme.violet)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)

            Text(AppLanguage.shared.s(
                "친구에게 코드를 공유하면\n크루에 합류할 수 있어요",
                "Share this code with friends\nso they can join the crew"
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

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

    // MARK: - Helpers

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    @MainActor
    private func doCreate() async {
        guard canCreate else { return }
        isLoading = true
        errorMessage = nil
        do {
            let crew = try await CrewManager.shared.createCrew(
                name: crewName.trimmingCharacters(in: .whitespaces),
                resetCycle: resetCycle,
                nickname: nicknameManager.nickname ?? ""
            )
            createdCrew = crew
        } catch let ckError as CKError {
            switch ckError.code {
            case .notAuthenticated:
                errorMessage = AppLanguage.shared.s(
                    "iCloud 로그인이 필요해요. 설정 → Apple 계정을 확인해 주세요.",
                    "iCloud sign-in required. Check Settings → Apple Account."
                )
            case .networkUnavailable, .networkFailure:
                errorMessage = AppLanguage.shared.s(
                    "네트워크 연결을 확인해 주세요.",
                    "Check your network connection."
                )
            case .permissionFailure:
                errorMessage = AppLanguage.shared.s(
                    "iCloud 접근 권한이 필요해요.",
                    "iCloud access permission required."
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
