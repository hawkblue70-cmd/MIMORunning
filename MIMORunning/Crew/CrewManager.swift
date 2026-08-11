import CloudKit

// MARK: - Models

struct Crew: Hashable {
    let recordID: CKRecord.ID
    let code: String
    let name: String
    let resetCycle: String   // "weekly" | "monthly"
    let createdAt: Date
    let ownerID: String
}

struct CrewMember {
    let recordID: CKRecord.ID
    let crewCode: String
    let nickname: String
    let icloudID: String
    var periodDistance: Double
    let joinedAt: Date
}

// MARK: - Errors

enum CrewError: LocalizedError {
    case crewNotFound
    case alreadyMember
    case tooManyCrews

    var errorDescription: String? {
        switch self {
        case .crewNotFound:  return "코드를 찾을 수 없어요"
        case .alreadyMember: return "이미 참여 중인 크루예요"
        case .tooManyCrews:  return "크루는 최대 3개까지 참여할 수 있어요"
        }
    }
}

// MARK: - Manager

final class CrewManager {
    static let shared = CrewManager()

    private let container = CKContainer(identifier: "iCloud.com.denny.MIMORunning")
    private var db: CKDatabase { container.publicCloudDatabase }

    private init() {}

    // MARK: - Code

    // 헷갈리는 문자(0/O, 1/I) 제외한 6자리 코드
    func generateCode() -> String {
        let chars = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    func userRecordID() async throws -> String {
        let recordID = try await container.userRecordID()
        return recordID.recordName
    }

    // MARK: - Crew

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
        return crewFrom(saved)
    }

    func findCrew(byCode code: String) async throws -> Crew? {
        let predicate = NSPredicate(format: "code == %@", code.uppercased())
        let query = CKQuery(recordType: "Crew", predicate: predicate)
        let (results, _) = try await db.records(matching: query, resultsLimit: 1)
        guard let first = results.first, let record = try? first.1.get() else { return nil }
        return crewFrom(record)
    }

    // MARK: - Member

    /// 크루 참여. 성공 시 크루 이름 반환.
    func joinCrew(code: String, nickname: String) async throws -> String {
        let upperCode = code.uppercased()
        let myID = try await userRecordID()

        // 크루 존재 확인
        guard let crew = try await findCrew(byCode: upperCode) else {
            throw CrewError.crewNotFound
        }

        // 중복 참여 체크 (crewCode + icloudID 복합 쿼리 — 두 필드 모두 Queryable 필요)
        let dupPred = NSPredicate(format: "crewCode == %@ AND icloudID == %@", upperCode, myID)
        let dupQuery = CKQuery(recordType: "CrewMember", predicate: dupPred)
        let dupResults = try await safeQuery(dupQuery, limit: 1)
        if dupResults.contains(where: { (try? $0.1.get()) != nil }) {
            throw CrewError.alreadyMember
        }

        // 최대 3개 크루 제한 (icloudID Queryable 필요)
        let countPred = NSPredicate(format: "icloudID == %@", myID)
        let countQuery = CKQuery(recordType: "CrewMember", predicate: countPred)
        let countResults = try await safeQuery(countQuery, limit: 4)
        let currentCount = countResults.filter { (try? $0.1.get()) != nil }.count
        if currentCount >= 3 {
            throw CrewError.tooManyCrews
        }

        // CrewMember 레코드 생성
        let memberRecord = CKRecord(recordType: "CrewMember")
        memberRecord["crewCode"] = upperCode
        memberRecord["nickname"] = nickname
        memberRecord["icloudID"] = myID
        memberRecord["periodDistance"] = 0.0
        memberRecord["joinedAt"] = Date()

        _ = try await db.save(memberRecord)
        return crew.name
    }

    // MARK: - My Crews

    /// 내가 속한 모든 크루를 (Crew, 인원수) 쌍으로 반환.
    func fetchMyCrews() async throws -> [(crew: Crew, memberCount: Int)] {
        let memberships = try await fetchMyMemberships()
        var entries: [(crew: Crew, memberCount: Int)] = []
        for m in memberships {
            guard let crew = try await findCrew(byCode: m.crewCode) else { continue }
            let count = try await fetchMemberCount(crewCode: m.crewCode)
            entries.append((crew: crew, memberCount: count))
        }
        return entries
    }

    private func fetchMyMemberships() async throws -> [CrewMember] {
        let myID = try await userRecordID()
        let pred = NSPredicate(format: "icloudID == %@", myID)
        let query = CKQuery(recordType: "CrewMember", predicate: pred)
        let results = try await safeQuery(query, limit: 10)
        return results.compactMap { _, result in
            guard let record = try? result.get() else { return nil }
            return memberFrom(record)
        }
    }

    private func fetchMemberCount(crewCode: String) async throws -> Int {
        let pred = NSPredicate(format: "crewCode == %@", crewCode)
        let query = CKQuery(recordType: "CrewMember", predicate: pred)
        let results = try await safeQuery(query, limit: 100)
        return results.filter { (try? $0.1.get()) != nil }.count
    }

    // MARK: - Ranking

    /// 내 CrewMember 레코드의 periodDistance(km)를 최신값으로 업데이트.
    func updateMyDistance(crewCode: String, distanceKm: Double) async throws {
        let myID = try await userRecordID()
        let pred = NSPredicate(format: "crewCode == %@ AND icloudID == %@", crewCode, myID)
        let query = CKQuery(recordType: "CrewMember", predicate: pred)
        let results = try await safeQuery(query, limit: 1)
        guard let first = results.first, let record = try? first.1.get() else { return }
        record["periodDistance"] = distanceKm
        _ = try await db.save(record)
    }

    /// 크루 전원의 CrewMember를 periodDistance 내림차순으로 반환.
    func fetchRanking(crewCode: String) async throws -> [CrewMember] {
        let pred = NSPredicate(format: "crewCode == %@", crewCode)
        let query = CKQuery(recordType: "CrewMember", predicate: pred)
        let results = try await safeQuery(query, limit: 200)
        let members = results
            .compactMap { _, result in try? result.get() }
            .map { memberFrom($0) }
            .sorted { $0.periodDistance > $1.periodDistance }
        #if DEBUG
        print("[CrewManager] fetchRanking code=\(crewCode) rawResults=\(results.count) parsed=\(members.count)")
        #endif
        return members
    }

    private func memberFrom(_ record: CKRecord) -> CrewMember {
        CrewMember(
            recordID: record.recordID,
            crewCode: record["crewCode"] as? String ?? "",
            nickname: record["nickname"] as? String ?? "",
            icloudID: record["icloudID"] as? String ?? "",
            periodDistance: record["periodDistance"] as? Double ?? 0,
            joinedAt: record["joinedAt"] as? Date ?? Date()
        )
    }

    // MARK: - Helpers

    /// CrewMember 타입이 아직 존재하지 않는 경우(첫 저장 전) unknownItem 에러를
    /// 빈 배열로 처리해 저장 단계까지 진행할 수 있게 한다.
    private func safeQuery(
        _ query: CKQuery,
        limit: Int
    ) async throws -> [(CKRecord.ID, Result<CKRecord, Error>)] {
        do {
            let (results, _) = try await db.records(matching: query, resultsLimit: limit)
            return results
        } catch let ckError as CKError {
            // 레코드 타입이 아직 없으면 CloudKit이 unknownItem을 반환
            if ckError.code == .unknownItem { return [] }
            throw ckError
        }
    }

    // MARK: - Owner

    func isOwner(crew: Crew) async throws -> Bool {
        let myID = try await userRecordID()
        return crew.ownerID == myID
    }

    // MARK: - Rename

    func renameCrew(crew: Crew, newName: String) async throws -> Crew {
        let record = try await db.record(for: crew.recordID)
        record["name"] = newName
        let saved = try await db.save(record)
        return crewFrom(saved)
    }

    // MARK: - Disband (방장 전용)

    func disbandCrew(crew: Crew) async throws {
        let pred = NSPredicate(format: "crewCode == %@", crew.code)
        let query = CKQuery(recordType: "CrewMember", predicate: pred)
        let results = try await safeQuery(query, limit: 200)
        let ids = results.compactMap { _, result in (try? result.get())?.recordID }
        for id in ids { try? await db.deleteRecord(withID: id) }
        try await db.deleteRecord(withID: crew.recordID)
    }

    // MARK: - Kick (방장 전용)

    func kickMember(_ member: CrewMember) async throws {
        try await db.deleteRecord(withID: member.recordID)
    }

    // MARK: - Leave (방장 승계 포함)

    /// 크루 나가기.
    /// - 방장 아님: 내 CrewMember만 삭제.
    /// - 방장 + 다른 멤버 있음: joinedAt 가장 이른 사람에게 ownerID 승계 후 내 레코드 삭제.
    /// - 방장 + 나 혼자: Crew 레코드 + 내 CrewMember 삭제(해체).
    func leaveCrew(crew: Crew) async throws {
        let myID = try await userRecordID()

        // 크루 전체 멤버 조회
        let pred = NSPredicate(format: "crewCode == %@", crew.code)
        let query = CKQuery(recordType: "CrewMember", predicate: pred)
        let results = try await safeQuery(query, limit: 200)
        let allMembers = results.compactMap { _, result in try? result.get() }.map { memberFrom($0) }

        guard let myMember = allMembers.first(where: { $0.icloudID == myID }) else { return }

        let amOwner = crew.ownerID == myID

        if !amOwner {
            // 일반 멤버: 내 레코드만 삭제
            try await db.deleteRecord(withID: myMember.recordID)
            return
        }

        let others = allMembers.filter { $0.icloudID != myID }

        if others.isEmpty {
            // 방장 + 나 혼자: 크루 해체
            try await db.deleteRecord(withID: myMember.recordID)
            try await db.deleteRecord(withID: crew.recordID)
            return
        }

        // 방장 + 다른 멤버: joinedAt 가장 이른 사람에게 승계
        let nextOwner = others.min(by: { $0.joinedAt < $1.joinedAt })!
        let crewRecord = try await db.record(for: crew.recordID)
        crewRecord["ownerID"] = nextOwner.icloudID
        _ = try await db.save(crewRecord)

        // 승계 완료 후 내 레코드 삭제
        try await db.deleteRecord(withID: myMember.recordID)
    }

    private func crewFrom(_ record: CKRecord) -> Crew {
        Crew(
            recordID: record.recordID,
            code: record["code"] as? String ?? "",
            name: record["name"] as? String ?? "",
            resetCycle: record["resetCycle"] as? String ?? "weekly",
            createdAt: record["createdAt"] as? Date ?? Date(),
            ownerID: record["ownerID"] as? String ?? ""
        )
    }
}
