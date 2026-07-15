import SwiftUI
import UIKit

/// `daram_chew_manifest.json`의 frame_layout 순서대로 PNG 스프라이트를 재생한다.
struct DaramChewingView: View {
    let size: CGSize
    let isPlaying: Bool
    let fps: Double

    @State private var playbackStartedAt = Date()

    init(size: CGSize, isPlaying: Bool, fps: Double = 8) {
        self.size = size
        self.isPlaying = isPlaying
        self.fps = fps
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: frameDuration, paused: !isPlaying)) { context in
            frameImage(at: context.date)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .onChange(of: isPlaying) { _, isOn in
            if isOn {
                playbackStartedAt = Date()
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func frameImage(at date: Date) -> some View {
        if let frame = Self.frames[safe: frameIndex(at: date)] {
            Image(uiImage: frame)
                .resizable()
                .interpolation(.none)
                .antialiased(false)
                .scaledToFit()
                .frame(width: size.width, height: size.height)
        } else {
            // 로드 실패 시 전체 시트를 노출하지 않는다.
            Color.clear
        }
    }

    private var effectiveFPS: Double {
        max(fps, 0.1)
    }

    private var frameDuration: TimeInterval {
        1 / effectiveFPS
    }

    private func frameIndex(at date: Date) -> Int {
        guard isPlaying, !Self.frames.isEmpty else { return 0 }
        let elapsed = max(0, date.timeIntervalSince(playbackStartedAt))
        return Int(elapsed * effectiveFPS) % Self.frames.count
    }

    private static let frames: [UIImage] = DaramChewingFrames.load()
}

private enum DaramChewingFrames {
    private static let sheetAssetName = "daram_chew_sheet"
    private static let manifestResourceName = "daram_chew_manifest"
    private static let animationName = "chew-rhythm"

    static func load(bundle: Bundle = .main) -> [UIImage] {
        guard
            let manifestURL = bundle.url(forResource: manifestResourceName, withExtension: "json"),
            let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(SpriteManifest.self, from: data),
            let layout = manifest.frameLayout.rows[animationName],
            let sheet = UIImage(named: sheetAssetName, in: bundle, compatibleWith: nil),
            let cgSheet = sheet.cgImage,
            cgSheet.width == manifest.frameLayout.sheetWidth,
            cgSheet.height == manifest.frameLayout.sheetHeight
        else {
            assertionFailure("다람이 씹기 스프라이트 또는 manifest를 불러오지 못했습니다.")
            return []
        }

        return layout.compactMap { frame in
            let rect = CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h)
            guard
                frame.w == manifest.frameLayout.cellWidth,
                frame.h == manifest.frameLayout.cellHeight,
                let cropped = cgSheet.cropping(to: rect)
            else {
                assertionFailure("다람이 씹기 스프라이트의 frame_layout이 유효하지 않습니다.")
                return nil
            }
            return UIImage(cgImage: cropped, scale: sheet.scale, orientation: sheet.imageOrientation)
        }
    }
}

private struct SpriteManifest: Decodable {
    let frameLayout: FrameLayout

    enum CodingKeys: String, CodingKey {
        case frameLayout = "frame_layout"
    }

    struct FrameLayout: Decodable {
        let sheetWidth: Int
        let sheetHeight: Int
        let cellWidth: Int
        let cellHeight: Int
        let rows: [String: [Frame]]

        enum CodingKeys: String, CodingKey {
            case sheetWidth
            case sheetHeight
            case cellWidth
            case cellHeight
            case rows
        }
    }

    struct Frame: Decodable {
        let x: Int
        let y: Int
        let w: Int
        let h: Int
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("재생") {
    DaramChewingView(
        size: CGSize(width: 180, height: 180),
        isPlaying: true
    )
    .padding()
}

#Preview("정지") {
    DaramChewingView(
        size: CGSize(width: 180, height: 180),
        isPlaying: false
    )
    .padding()
}
