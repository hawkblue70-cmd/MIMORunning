import SwiftUI
import Combine
import StoreKit
import Security

// MARK: - Keychain Helper (앱 삭제 후 재설치로 구독 우회 방지)

enum KeychainHelper {
    private static let service = "kr.mimo.MIMORunning.pro"

    static func save(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrAccount as String:  key,
            kSecAttrService as String:  service,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Pro Manager

@MainActor
final class ProManager: ObservableObject {
    static let shared = ProManager()

    // App Store Connect에서 생성한 구독 상품 ID
    static let sixMonthID = "com.denny.mimorunning.pro"
    private static let allProductIDs: Set<String> = [sixMonthID]

    @Published var isPro = false
    @Published var products: [Product] = []
    @Published var purchaseError: String?
    @Published var introEligibility: [String: Bool] = [:]

    private(set) var firstLaunchDate: Date

    private static let firstLaunchKey = "firstLaunchDate"

    var trialEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 14, to: firstLaunchDate) ?? firstLaunchDate
    }
    var isTrialActive:  Bool { !isPro && Date() < trialEndDate }
    var isTrialExpired: Bool { !isPro && Date() >= trialEndDate }
    var daysRemainingInTrial: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let end   = Calendar.current.startOfDay(for: trialEndDate)
        return max(0, Calendar.current.dateComponents([.day], from: today, to: end).day ?? 0)
    }

    private var transactionListener: Task<Void, Never>?

    private init() {
        // Keychain에서 읽기 — 앱 삭제 후 재설치해도 날짜 유지
        if let str = KeychainHelper.load(forKey: Self.firstLaunchKey),
           let d = ISO8601DateFormatter().date(from: str) {
            firstLaunchDate = d
        } else {
            // 최초 설치: UserDefaults에 기존 값이 있으면 마이그레이션
            let now: Date
            if let legacy = UserDefaults.standard.object(forKey: "kr.mimo.running.firstLaunchDate") as? Date {
                now = legacy
            } else {
                now = Date()
            }
            firstLaunchDate = now
            KeychainHelper.save(ISO8601DateFormatter().string(from: now), forKey: Self.firstLaunchKey)
        }
        transactionListener = listenForTransactions()
        Task { await checkEntitlements() }
    }

    deinit { transactionListener?.cancel() }

    // MARK: - StoreKit 2

    @Published var productLoadError: String?

    func loadProducts() async {
        productLoadError = nil
        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            if loaded.isEmpty {
                productLoadError = "상품 정보를 불러올 수 없습니다. App Store Connect에서 구독 상품이 등록되어 있는지 확인하세요."
            }
            products = loaded.sorted { $0.price < $1.price }
            for p in products {
                if let sub = p.subscription {
                    introEligibility[p.id] = await sub.isEligibleForIntroOffer
                }
            }
        } catch {
            productLoadError = "상품 로드 실패: \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async -> Bool {
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let tx = try checkVerified(verification)
                await tx.finish()
                await checkEntitlements()
                return true
            case .userCancelled:
                return false
            case .pending:
                purchaseError = "결제 승인 대기 중입니다. 완료되면 자동으로 반영돼요."
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        do { try await AppStore.sync() } catch { }
        await checkEntitlements()
    }

    func checkEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if let tx = try? checkVerified(result),
               Self.allProductIDs.contains(tx.productID) {
                isPro = true
                return
            }
        }
        isPro = false
    }

    // MARK: - Helpers

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let value):      return value
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let tx = try? self?.checkVerified(result) {
                    await tx.finish()
                    await self?.checkEntitlements()
                }
            }
        }
    }
}
