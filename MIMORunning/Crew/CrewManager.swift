import CloudKit

struct Crew {
    let recordID: CKRecord.ID
    let code: String
    let name: String
    let resetCycle: String   // "weekly" | "monthly"
    let createdAt: Date
    let ownerID: String
}

final class CrewManager {
    static let shared = CrewManager()

    private let container = CKContainer(identifier: "iCloud.com.denny.MIMORunning")
    private var db: CKDatabase { container.publicCloudDatabase }

    private init() {}

    // 헷갈리는 문자(0/O, 1/I) 제외한 6자리 코드
    func generateCode() -> String {
        let chars = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    func userRecordID() async throws -> String {
        let recordID = try await container.userRecordID()
        return recordID.recordName
    }

    func createCrew(name: String, resetCycle: String) async throws -> Crew {
        let ownerID = try await userRecordID()
        let code = generateCode()

        let record = CKRecord(recordType: "Crew")
        record["code"] = code
        record["name"] = name
        record["resetCycle"] = resetCycle
        record["createdAt"] = Date()
        record["ownerID"] = ownerID

        let saved = try await db.save(record)

        return Crew(
            recordID: saved.recordID,
            code: saved["code"] as? String ?? code,
            name: saved["name"] as? String ?? name,
            resetCycle: saved["resetCycle"] as? String ?? resetCycle,
            createdAt: saved["createdAt"] as? Date ?? Date(),
            ownerID: saved["ownerID"] as? String ?? ownerID
        )
    }
}
