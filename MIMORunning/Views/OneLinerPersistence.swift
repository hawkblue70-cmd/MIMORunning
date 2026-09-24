// OneLiner 카드 — SwiftData 영속화 헬퍼
//
// OneLinerEntry(SwiftData) 읽기·쓰기·마이그레이션 전담.
// ShareCardView.swift에서 추출. extension ShareCardScreen 으로 타입 상태에 직접 접근.

import SwiftUI
import SwiftData
import PhotosUI

extension ShareCardScreen {

    // MARK: - OneLiner persistence (SwiftData, per media ref)

    /// mediaRef key for the currently active OneLiner entry.
    private func computeOneLinerMediaRef() -> String? {
        guard isOneLiner else { return nil }
        if template == .video, let assetID = videoPickerItem?.itemIdentifier {
            return "video:\(assetID)"
        }
        if template == .photo {
            let idx = cardPhotoIndex[.oneLiner] ?? 0
            if idx < oneLinerVM.storyPhotoUUIDs.count { return "photo:\(oneLinerVM.storyPhotoUUIDs[idx])" }
        }
        return nil   // gradient
    }

    func findOrCreateOneLinerEntry(for mediaRef: String?) -> OneLinerEntry {
        if let existing = oneLinerEntries.first(where: { $0.mediaRef == mediaRef }) {
            return existing
        }
        let entry = OneLinerEntry(workoutID: activity.id.uuidString, mediaRef: mediaRef)
        modelContext.insert(entry)
        return entry
    }

    // MARK: - UI ↔ SwiftData 동기화

    private func syncUIFromEntry(_ entry: OneLinerEntry) {
        // v3slide\n 포맷(ClipTrimSheet 저장)이면 실제 텍스트와 스타일을 디코딩.
        // 그렇지 않으면 레거시 플레인텍스트 방식 유지.
        if entry.text.hasPrefix("v3slide\n"),
           let data = entry.text.dropFirst("v3slide\n".count).data(using: .utf8),
           let desc = try? JSONDecoder().decode(SavedClipDescriptor.self, from: data) {
            oneLinerVM.oneLinerText     = desc.lines.filter { line in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty || t.hasPrefix("v3slide") || t.hasPrefix("v3recipes")
                    || t.hasPrefix("v4recipes") || t.hasPrefix("v2clips")
                    || (t.count > 30 && t.hasPrefix("{") && t.hasSuffix("}")) { return false }
                return true
            }.joined(separator: "\n")
            oneLinerVM.oneLinerFont     = OneLinerFont.migrate(desc.fontID)
            oneLinerVM.oneLinerColor    = desc.colorID.flatMap { OneLinerTextColor(rawValue: $0) } ?? .white
            if let aIdx = desc.anchorIdx, CardPosition.allCases.indices.contains(aIdx) {
                oneLinerVM.oneLinerPosition = CardPosition.allCases[aIdx]
            }
        } else {
            oneLinerVM.oneLinerText     = entry.text
            oneLinerVM.oneLinerFont     = entry.font
            oneLinerVM.oneLinerColor    = entry.textColor
            oneLinerVM.oneLinerPosition = entry.position
        }
    }

    // MARK: - 설정 로드

    func loadOneLinerSettings() {
        migrateUserDefaultsOneLiner()
        let mediaRef = computeOneLinerMediaRef()
        if let entry = oneLinerEntries.first(where: { $0.mediaRef == mediaRef }) {
            syncUIFromEntry(entry)
            oneLinerVM.oneLinerPhAssetDeleted = !entry.isPHAssetAvailable
            // Video slot mode: split saved text back into individual slot fields
            if template == .video && oneLinerVM.oneLinerVideoSlotCount > 2 {
                let lines = entry.text.components(separatedBy: "\n")
                oneLinerVM.oneLinerVideoSlotTexts = (0..<oneLinerVM.oneLinerVideoSlotCount).map { i in
                    i < lines.count ? lines[i] : ""
                }
            }
        } else {
            oneLinerVM.oneLinerText = ""
            oneLinerVM.oneLinerPhAssetDeleted = false
            // 연재 연속성: 새 사진에 처음 문구를 쓸 때 폰트·색은 직전 entry 기본값으로.
            // 위치(9앵커)는 사진마다 독립 — 사진 구도가 다르므로 그대로 유지.
            if let latest = oneLinerEntries.last {
                oneLinerVM.oneLinerFont  = latest.font
                oneLinerVM.oneLinerColor = latest.textColor
            }
            // Video slot mode: clear all slot fields
            if template == .video {
                oneLinerVM.oneLinerVideoSlotTexts = Array(repeating: "", count: max(2, oneLinerVM.oneLinerVideoSlotCount))
            }
        }
        loadOneLinerClipRecipes()
    }

    /// 명시적 photoIndex로 OneLiner entry 로드.
    /// cardPhotoIndex가 아직 커밋되지 않은 Button 액션 내에서 호출 시 사용.
    func loadOneLinerSettingsFor(photoIndex: Int) {
        migrateUserDefaultsOneLiner()
        let mediaRef: String? = photoIndex < oneLinerVM.storyPhotoUUIDs.count
            ? "photo:\(oneLinerVM.storyPhotoUUIDs[photoIndex])"
            : nil
        if let entry = oneLinerEntries.first(where: { $0.mediaRef == mediaRef }) {
            syncUIFromEntry(entry)
            oneLinerVM.oneLinerPhAssetDeleted = !entry.isPHAssetAvailable
        } else {
            oneLinerVM.oneLinerText = ""
            oneLinerVM.oneLinerPhAssetDeleted = false
            if let latest = oneLinerEntries.last {
                oneLinerVM.oneLinerFont  = latest.font
                oneLinerVM.oneLinerColor = latest.textColor
            }
        }
    }

    // MARK: - 설정 저장

    // 저장 트리거 전체 (모두 이 함수를 경유 → upsert 또는 delete-on-empty, append 경로 없음):
    // ① onChange(of: oneLinerVM.oneLinerText)   — 키 입력마다
    // ② 9앵커(position) 칩 탭
    // ③ 폰트 칩 탭
    // ④ 색 칩 탭
    // ⑤ 썸네일 탭                    — cardPhotoIndex 커밋 전에 이전 사진 entry 저장
    func saveOneLinerSettings() {
        let mediaRef = computeOneLinerMediaRef()
        let trimmed  = oneLinerVM.oneLinerText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = oneLinerEntries.first(where: { $0.mediaRef == mediaRef }) {
            // 빈 문구: 기존 entry 삭제 — 빈 텍스트 entry 잔류 방지
            if trimmed.isEmpty {
                modelContext.delete(existing)
                try? modelContext.save()
                return
            }
            // 변경 없으면 스킵
            guard existing.text      != oneLinerVM.oneLinerText     ||
                  existing.font      != oneLinerVM.oneLinerFont     ||
                  existing.textColor != oneLinerVM.oneLinerColor    ||
                  existing.position  != oneLinerVM.oneLinerPosition else { return }
            existing.text      = oneLinerVM.oneLinerText
            existing.font      = oneLinerVM.oneLinerFont
            existing.textColor = oneLinerVM.oneLinerColor
            existing.position  = oneLinerVM.oneLinerPosition
            try? modelContext.save()
            return
        }

        // 신규 entry: 문구가 있고 5개 미만일 때만 생성
        guard !trimmed.isEmpty, oneLinerEntries.count < 5 else { return }
        let entry = OneLinerEntry(workoutID: activity.id.uuidString, mediaRef: mediaRef)
        entry.text      = oneLinerVM.oneLinerText
        entry.font      = oneLinerVM.oneLinerFont
        entry.textColor = oneLinerVM.oneLinerColor
        entry.position  = oneLinerVM.oneLinerPosition
        modelContext.insert(entry)
        try? modelContext.save()
    }

    // MARK: - 중복 정리

    /// 중복·빈 문구 entry 정리.
    /// - nil mediaRef = "그라데이션 슬롯" — 러닝당 최대 1개로 취급 (nil끼리도 중복 처리됨).
    /// - 빈 텍스트 entry도 함께 제거.
    func deduplicateOneLinerEntries() {
        var toDelete: [OneLinerEntry] = []

        // ① 빈 텍스트 entry
        for entry in oneLinerEntries where entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            toDelete.append(entry)
        }

        // ② 같은 (workoutID + mediaRef) 중복 — nil도 단일 슬롯으로 처리
        let deleteIDs = Set(toDelete.map { ObjectIdentifier($0) })
        let remaining = oneLinerEntries.filter { !deleteIDs.contains(ObjectIdentifier($0)) }
        // Dictionary<String?, [OneLinerEntry]> — nil은 Optional.none 키로 그룹됨 ✓
        let grouped = Dictionary(grouping: remaining) { $0.mediaRef as String? }
        for (_, entries) in grouped where entries.count > 1 {
            let sorted = entries.sorted { $0.createdAt > $1.createdAt }
            toDelete.append(contentsOf: sorted.dropFirst())
        }

        guard !toDelete.isEmpty else { return }
        toDelete.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    // MARK: - UserDefaults → SwiftData 마이그레이션

    /// One-time migration: lift existing UserDefaults entry → SwiftData with mediaRef = nil.
    private func migrateUserDefaultsOneLiner() {
        let id = activity.id.uuidString
        let key = "oneliner_text_\(id)"
        guard let text = UserDefaults.standard.string(forKey: key), !text.isEmpty,
              !oneLinerEntries.contains(where: { $0.mediaRef == nil }) else { return }
        let entry = OneLinerEntry(workoutID: id, mediaRef: nil)
        entry.text = text
        if let raw = UserDefaults.standard.string(forKey: "oneliner_font_\(id)"),
           let f = OneLinerFont(rawValue: raw) { entry.font = f }
        if let raw = UserDefaults.standard.string(forKey: "oneliner_color_\(id)"),
           let c = OneLinerTextColor(rawValue: raw) { entry.textColor = c }
        let posIdx = UserDefaults.standard.integer(forKey: "oneliner_pos_\(id)")
        let cases = Array(CardPosition.allCases)
        if posIdx < cases.count { entry.position = cases[posIdx] }
        if UserDefaults.standard.object(forKey: "oneliner_date_\(id)") != nil {
            entry.showDate = UserDefaults.standard.bool(forKey: "oneliner_date_\(id)")
        }
        modelContext.insert(entry)
        try? modelContext.save()
        ["text", "font", "color", "pos", "date"].forEach {
            UserDefaults.standard.removeObject(forKey: "oneliner_\($0)_\(id)")
        }
    }
}
