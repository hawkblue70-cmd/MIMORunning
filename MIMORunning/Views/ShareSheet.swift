import SwiftUI

// MARK: - UIActivityViewController wrapper (static image 공유 전용)

// UIImage를 직접 전달 — Instagram은 파일 URL(특히 PNG)을 거부하므로 UIImage 객체를 전달해야 함
struct ShareSheet: UIViewControllerRepresentable {
    let images: [UIImage]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: images, applicationActivities: nil)
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
