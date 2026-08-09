import SwiftUI

@Observable final class CrewNicknameManager {
    private let key = "crew.nickname.v1"

    private(set) var nickname: String?

    init() {
        let stored = UserDefaults.standard.string(forKey: key)
        nickname = (stored?.isEmpty == false) ? stored : nil
    }

    func save(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard isValid(trimmed) else { return }
        nickname = trimmed
        UserDefaults.standard.set(trimmed, forKey: key)
    }

    func isValid(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 2 && trimmed.count <= 12
    }
}
