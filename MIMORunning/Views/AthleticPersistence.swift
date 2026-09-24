// Athletic 카드 — 사진 크롭 위치(스토리 가로 크롭·슬라이드 사진별 크롭) UserDefaults 저장·복원.
// (플레이서블 카드 삭제 때 PlaceablePersistence.swift에서 옮김 — 저장 키는 그대로라 기존 값이 이어진다)

import SwiftUI

extension ShareCardScreen {

    // MARK: - Athletic 크롭 저장·복원

    var athleticCropPrefix: String { "athletic_\(activity.id.uuidString)_" }

    func saveAthleticCropOffsets() {
        let ud = UserDefaults.standard
        let p  = athleticCropPrefix
        ud.set(Double(athleticCropOffsetX), forKey: p + "cropX")
        let dict = Dictionary(uniqueKeysWithValues: athleticSlideCropOffsets.map { (String($0.key), Double($0.value)) })
        if let data = try? JSONEncoder().encode(dict) { ud.set(data, forKey: p + "slideCropOffsets") }
    }

    func loadAthleticCropOffsets() {
        let ud = UserDefaults.standard
        let p  = athleticCropPrefix
        if ud.object(forKey: p + "cropX") != nil {
            athleticCropOffsetX = CGFloat(ud.double(forKey: p + "cropX"))
        }
        if let data = ud.data(forKey: p + "slideCropOffsets"),
           let dict = try? JSONDecoder().decode([String: Double].self, from: data) {
            athleticSlideCropOffsets = Dictionary(uniqueKeysWithValues:
                dict.compactMap { k, v in Int(k).map { ($0, CGFloat(v)) } })
        }
    }
}
