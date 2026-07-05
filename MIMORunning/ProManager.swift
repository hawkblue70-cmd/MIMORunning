import SwiftUI
import StoreKit
import Security
import CloudKit
import Observation

// MARK: - Keychain Helper (앱 삭제 후 재설치로 체험 기간 우회 방지)

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
@Observable
final class ProManager {
    static let shared = ProManager()

    // 개발자 iCloud 계정 식별자 — 첫 실행 후 콘솔에서 "[ProMgr] CloudKit ID:" 로그로 확인
    private static let developerCloudKitID = "_278335aa7345fdb9ed107eed61d2cdb0"

    // App Store Connect 구독 상품 ID (6개월)
    static let sixMonthID = "com.denny.mimorunning.pro"
    private static let allProductIDs: Set<String> = [sixMonthID]

    // CloudKit — MIMOApp과 공유 컨테이너로 개발자 계정 인식
    private static let sharedContainerID    = "iCloud.com.denny.MimoSubscription"
    private static let subscriptionRecordID = CKRecord.ID(recordName: "mimo-running-pro-subscription")

    static let trialDays = 14

    var isPro            = false
    var products: [Product] = []
    var purchaseError: String?
    var productLoadError: String?
    var introEligibility: [String: Bool] = [:]

    private(set) var firstLaunchDate: Date

    private(set) var lastSubscriptionEndDate: Date? {
        didSet {
            if let d = lastSubscriptionEndDate {
                UserDefaults.standard.set(d, forKey: Self.subscriptionEndDateKey)
            }
        }
    }

    private static let firstLaunchKey        = "firstLaunchDate"
    private static let subscriptionEndDateKey = "kr.mimo.running.subscriptionEndDate"

    var trialEndDate: Date {
        Calendar.current.date(byAdding: .day, value: Self.trialDays, to: firstLaunchDate) ?? firstLaunchDate
    }

    var effectiveCutoffDate: Date {
        guard let subEnd = lastSubscriptionEndDate else { return trialEndDate }
        return max(trialEndDate, subEnd)
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
            let now: Date
            if let legacy = UserDefaults.standard.object(forKey: "kr.mimo.running.firstLaunchDate") as? Date {
                now = legacy
            } else {
                now = Date()
            }
            firstLaunchDate = now
            KeychainHelper.save(ISO8601DateFormatter().string(from: now), forKey: Self.firstLaunchKey)
        }
        lastSubscriptionEndDate = UserDefaults.standard.object(forKey: Self.subscriptionEndDateKey) as? Date
        transactionListener = listenForTransactions()
        Task { await checkEntitlements() }
    }


    // MARK: - StoreKit 2

    func loadProducts() async {
        productLoadError = nil
        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            if loaded.isEmpty {
                productLoadError = "상품 정보를 불러올 수 없습니다. App Store Connect에서 구독 상품이 등록되어 있는지 확인하세요."
            }
            products = loaded
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
                if let exp = tx.expirationDate {
                    lastSubscriptionEndDate = exp
                    await saveSubscriptionToCloud(expiryDate: exp)
                }
                return
            }
        }
        // 개발자 계정 → 자동 Pro
        if await isDeveloperAccount() { isPro = true; return }
        // CloudKit 백업 확인 (구독 만료 직후 영수증 전파 지연 보완)
        if await checkCloudSubscription() { isPro = true; return }
        isPro = false
    }

    // MARK: - CloudKit

    private func saveSubscriptionToCloud(expiryDate: Date) async {
        let db = CKContainer(identifier: Self.sharedContainerID).privateCloudDatabase
        do {
            let record: CKRecord
            do {
                record = try await db.record(for: Self.subscriptionRecordID)
            } catch {
                record = CKRecord(recordType: "MimoSubscription", recordID: Self.subscriptionRecordID)
            }
            record["expiryDate"] = expiryDate
            try await db.save(record)
        } catch { }
    }

    private func checkCloudSubscription() async -> Bool {
        let db = CKContainer(identifier: Self.sharedContainerID).privateCloudDatabase
        do {
            let record = try await db.record(for: Self.subscriptionRecordID)
            if let exp = record["expiryDate"] as? Date { return exp > Date() }
        } catch { }
        return false
    }

    private func isDeveloperAccount() async -> Bool {
        do {
            let id = try await CKContainer.default().userRecordID()
            guard !Self.developerCloudKitID.isEmpty else { return false }
            return id.recordName == Self.developerCloudKitID
        } catch {
            return false
        }
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
