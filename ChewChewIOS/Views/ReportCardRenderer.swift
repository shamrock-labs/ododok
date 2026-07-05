import SwiftUI
import UniformTypeIdentifiers

/// `ReportCardView`를 1080×1920 PNG로 렌더링하는 Transferable 페이로드.
/// PRD #4 — 인스타 스토리 비율(9:16) + scale 3.0. ShareLink에 그대로 전달하면
/// 시스템 공유 시트가 PNG 첨부로 인식한다.
struct ReportCardSharePayload: Transferable, Sendable {
    let imageData: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.imageData }
            .suggestedFileName("chew-report.png")
    }
}

/// `ReportCardView`를 PNG `Data`로 렌더링. SwiftUI `ImageRenderer`는 `@MainActor`라
/// 호출자도 main 컨텍스트여야 함. 카드 자체에는 `padding`/배경이 없어서 export 시
/// `Color.cream` 위에 카드를 한 번 더 얹어 일관된 frame을 만든다.
@MainActor
enum ReportCardRenderer {
    /// 1080×1920(9:16) scale 3.0 PNG. 실패 시 nil.
    static func render(_ model: ReportCardModel) -> Data? {
        let content = ZStack {
            Color.cream
            ReportCardView(model: model, rendersStatically: true)
                .padding(.horizontal, AppSpacing.page)
        }
        .frame(width: Metrics.shareImageWidth, height: Metrics.shareImageHeight)
        // 공유 PNG는 기기 다크모드와 무관하게 항상 라이트로 렌더(동적 토큰이 dark로 뒤집혀
        // cream 배경 위에 다크 카드가 그려지는 것 방지).
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: content)
        renderer.scale = Metrics.shareImageScale
        return renderer.uiImage?.pngData()
    }
}

private enum Metrics {
    static let shareImageWidth: CGFloat = 360
    static let shareImageHeight: CGFloat = 640
    static let shareImageScale: CGFloat = 3
}
