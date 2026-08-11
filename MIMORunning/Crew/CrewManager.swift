import CloudKit

// MARK: - Models

struct Crew: Hashable {
    let recordID: CKRecord.ID
    let code: String
    let name: String
    let resetCycle: String   // "weekly" | "monthly"
    let createdAt: Date
    let ownerID: String
    let kickedMemberIDs: [String]
}

struct CrewMember {
    let recordID: CKRecord.ID
    let crewCode: String
    let nickname: String
    let icloudID: String
    var periodDistance: Double
    var lastPeriodDistance: Double
    let joinedAt: Date
}

// MARK: - Errors

enum CrewError: LocalizedError {
    case crewNotFound
    case alreadyMember
    case tooManyCrews
    case kicked

    var errorDescription: String? {
        switch self {
        case .crewNotFound:  return AppLanguage.shared.s("코드를 찾을 수 없어요", "Crew not found")
        case .alreadyMember: return AppLanguage.shared.s("이미 참여 중인 크루예요", "Already a member")
        case .tooManyCrews:  return AppLanguage.shared.s("크루는 최대 3개까지 참여할 수 있어요", "You can join up to 3 crews")
        case .kicked:        return AppLanguage.shared.s("이 크루에서 내보내진 상태예요", "You've been removed from this crew")
        }
    }
}

// MARK: - Manager

final class CrewManager {
    static let shared = CrewManager()

    private let container = CKContainer(identifier: "iCloud.com.denny.MIMORunning")
    private var db: CKDatabase { container.publicCloudDatabase }

    private init() {}

    // MARK: - User ID (세션 내 캐싱 — iCloud 계정이 바뀌지 않는 한 불변)

    private var cachedUserID: String?

    // MARK: - Code

    // 헷갈리는 문자(0/O, 1/I) 제외한 6자리 코드
    func generateCode() -> String {
        let chars = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    func userRecordID() async throws -> String {
        if let cached = cachedUserID { return cached }
        let id = try await container.userRecordID().recordName
        cachedUserID = id
        return id
    }

    // MARK: - Crew

    func createCrew(name: String, resetCycle: String, nickname: String) async throws -> Crew {
        let ownerID = try await userRecordID()
        let code = generateCode()

        let record = CKRecord(recordType: "Crew")
        record["code"] = code
        record["name"] = name
        record["resetCycle"] = resetCycle
        record["createdAt"] = Date()
        record["ownerID"] = ownerID

        let saved = try await db.save(record)
        let crew = crewFrom(saved)

        // 방장의 CrewMember 레코드 생성 (fetchMyCrews가 CrewMember 기반으로 동작)
        let memberRecord = CKRecord(recordType: "CrewMember")
        memberRecord["crewCode"] = code
        memberRecord["nickname"] = nickname
        memberRecord["icloudID"] = ownerID
        memberRecord["periodDistance"] = 0.0
        memberRecord["joinedAt"] = Date()
        _ = try await db.save(memberRecord)

        return crew
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

        // 강퇴 여부 확인 (크루 레코드에 kickedMemberIDs 기록됨)
        if crew.kickedMemberIDs.contains(myID) {
            throw CrewError.kicked
        }

        // 이 크루의 전체 멤버를 가져온 뒤 클라이언트에서 icloudID 필터링.
        // 복합 조건 AND icloudID 는 icloudID 가 Queryable 이 아닐 때 false-positive 반환하므로
        // crewCode 단일 조건(Queryable 보장)으로 가져와 코드에서 검사한다.
        let crewMembersPred = NSPredicate(format: "crewCode == %@", upperCode)
        let crewMembersQuery = CKQuery(recordType: "CrewMember", predicate: crewMembersPred)
        let crewMembersResults = try await safeQuery(crewMembersQuery, limit: 200)
        let crewMembers = crewMembersResults.compactMap { try? $0.1.get() }

        // 이 시점에서 myID 는 kickedMemberIDs 에 없음이 확인됨.
        // 강퇴된 멤버의 CrewMember 레코드가 삭제 없이 남아있더라도,
        // 강퇴 체크를 먼저 통과한 경우만 여기 도달하므로 단순 icloudID 비교로 충분하다.
        if crewMembers.contains(where: { ($0["icloudID"] as? String) == myID }) {
            throw CrewError.alreadyMember
        }

        // 최대 3개 크루 제한: 내 icloudID 가 포함된 다른 크루 레코드 수를 세기 위해
        // fetchMyMemberships 를 통해 조회. icloudID Queryable 미설정 시 에러 처리.
        let currentCount: Int
        do {
            let myMemberships = try await fetchMyMemberships()
            currentCount = myMemberships.count
        } catch {
            currentCount = 0
        }
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

    /// 내가 속한 모든 크루를 (Crew, 인원수) 쌍으로 반환. 강퇴된 크루는 제외.
    /// 각 크루 조회를 병렬로 실행해 CloudKit 왕복 횟수를 최소화한다.
    func fetchMyCrews() async throws -> [(crew: Crew, memberCount: Int)] {
        let memberships = try await fetchMyMemberships()
        let myID = try await userRecordID()

        return try await withThrowingTaskGroup(of: (crew: Crew, memberCount: Int)?.self) { group in
            for m in memberships {
                group.addTask {
                    guard let crew = try await self.findCrew(byCode: m.crewCode) else { return nil }
                    if crew.kickedMemberIDs.contains(myID) { return nil }
                    let count = try await self.fetchMemberCount(crewCode: m.crewCode, kickedIDs: crew.kickedMemberIDs)
                    return (crew: crew, memberCount: count)
                }
            }
            var entries: [(crew: Crew, memberCount: Int)] = []
            for try await entry in group {
                if let e = entry { entries.append(e) }
            }
            return entries
        }
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

    private func fetchMemberCount(crewCode: String, kickedIDs: [String]) async throws -> Int {
        let pred = NSPredicate(format: "crewCode == %@", crewCode)
        let query = CKQuery(recordType: "CrewMember", predicate: pred)
        let results = try await safeQuery(query, limit: 100)
        return results
            .compactMap { _, result in try? result.get() }
            .filter { !kickedIDs.contains($0["icloudID"] as? String ?? "") }
            .count
    }

    // MARK: - Ranking

    /// 내 CrewMember 레코드의 periodDistance(현재)와 lastPeriodDistance(직전)를 업데이트.
    func updateMyDistance(crewCode: String, distanceKm: Double, lastDistanceKm: Double) async throws {
        let myID = try await userRecordID()
        // crewCode 단일 조건으로 쿼리 후 클라이언트에서 icloudID 필터링 (복합 조건 false-positive 방지)
        let pred = NSPredicate(format: "crewCode == %@", crewCode)
        let query = CKQuery(recordType: "CrewMember", predicate: pred)
        let results = try await safeQuery(query, limit: 200)
        guard let record = results
            .compactMap({ try? $0.1.get() })
            .first(where: { ($0["icloudID"] as? String) == myID })
        else { return }
        record["periodDistance"] = distanceKm
        record["lastPeriodDistance"] = lastDistanceKm
        _ = try await db.save(record)
    }

    /// 크루 전원의 CrewMember를 periodDistance 내림차순으로 반환. 강퇴된 멤버 제외.
    func fetchRanking(crew: Crew) async throws -> [CrewMember] {
        let pred = NSPredicate(format: "crewCode == %@", crew.code)
        let query = CKQuery(recordType: "CrewMember", predicate: pred)
        let results = try await safeQuery(query, limit: 200)
        let members = results
            .compactMap { _, result in try? result.get() }
            .map { memberFrom($0) }
            .filter { !crew.kickedMemberIDs.contains($0.icloudID) }
            .sorted { $0.periodDistance > $1.periodDistance }
        #if DEBUG
        print("[CrewManager] fetchRanking code=\(crew.code) rawResults=\(results.count) parsed=\(members.count) kicked=\(crew.kickedMemberIDs.count)")
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
            lastPeriodDistance: record["lastPeriodDistance"] as? Double ?? 0,
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
    // CloudKit Public DB는 레코드 생성자만 삭제 가능하므로,
    // Crew 레코드(방장 소유)에 kickedMemberIDs를 기록해 필터링하는 방식으로 구현.

    func kickMember(_ member: CrewMember, fromCrew crew: Crew) async throws {
        let crewRecord = try await db.record(for: crew.recordID)
        var kicked = crewRecord["kickedMemberIDs"] as? [String] ?? []
        if !kicked.contains(member.icloudID) {
            kicked.append(member.icloudID)
        }
        crewRecord["kickedMemberIDs"] = kicked as CKRecordValue
        _ = try await db.save(crewRecord)
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

        // 강퇴된 멤버의 CrewMember 레코드는 CloudKit 권한상 삭제 불가로 남아 있으므로
        // 최신 kickedMemberIDs 를 Crew 레코드에서 직접 읽어 제외한다.
        let crewRecord = try await db.record(for: crew.recordID)
        let freshKickedIDs = Set(crewRecord["kickedMemberIDs"] as? [String] ?? [])
        let eligibleOthers = allMembers.filter {
            $0.icloudID != myID && !freshKickedIDs.contains($0.icloudID)
        }

        if eligibleOthers.isEmpty {
            // 방장 + 유효 멤버 없음(전원 강퇴 또는 나 혼자): 크루 해체
            try await db.deleteRecord(withID: myMember.recordID)
            try await db.deleteRecord(withID: crew.recordID)
            return
        }

        // 방장 + 다른 멤버: joinedAt 가장 이른 사람에게 승계
        let nextOwner = eligibleOthers.min(by: { $0.joinedAt < $1.joinedAt })!
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
            ownerID: record["ownerID"] as? String ?? "",
            kickedMemberIDs: record["kickedMemberIDs"] as? [String] ?? []
        )
    }
}
