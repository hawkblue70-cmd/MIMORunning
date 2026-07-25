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

// MARK: - UIActivityViewController wrapper (영상 URL 공유 전용)

// ShareLink + FileRepresentation은 첫 탭에서 준비 지연이 발생하므로 URL을 직접 전달.
struct VideoShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
