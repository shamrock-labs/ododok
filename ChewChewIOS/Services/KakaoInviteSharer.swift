import Foundation
import SwiftUI
import UIKit
import KakaoSDKShare
import KakaoSDKTemplate

/// 친구 초대를 카카오톡 인앱 공유로 보낸다(링크 복사 아님 — 카카오톡 공유 시트가 직접 뜬다).
/// 맨 마스코트 대신 디자인된 초대 배너(InviteCardImage)를 렌더해 카드 이미지로 쓰며,
/// 받은 사람이 버튼을 누르면 `code` 파라미터로 앱이 열려 자동 수락 흐름으로 이어진다.
enum KakaoInviteSharer {

    enum ShareError: Error {
        case noCode
        case kakaoTalkUnavailable
        case imageUnavailable
    }

    /// 카드 이미지 디자인 버전. 배너 디자인이 바뀌면 올려서 캐시(업로드된 URL)를 무효화한다.
    private static let imageDesignVersion = 2
    private static var cachedImageUrlKey: String {
        "ChewChewIOS.KakaoInvite.cardImageUrl.v\(imageDesignVersion)"
    }

    /// 초대 코드로 카카오 공유 시트를 띄운다. 성공 시 카카오톡이 열린다.
    @MainActor
    static func share(code: String) async throws {
        guard !code.isEmpty else { throw ShareError.noCode }
        // 카카오톡 미설치 시 공유 시트가 뜨지 않으므로 호출부에서 안내한다.
        guard ShareApi.isKakaoTalkSharingAvailable() else { throw ShareError.kakaoTalkUnavailable }

        let imageUrl = try await invitationImageURL()
        // 받은 앱이 code 파라미터로 초대 코드를 수신하도록 iosExecutionParams에 실어 보낸다.
        let link = Link(iosExecutionParams: ["code": code])
        let template = FeedTemplate(
            content: Content(
                title: "같이 식사 목표 채워요",
                imageUrl: imageUrl,
                link: link
            ),
            buttons: [Button(title: "친구 되기", link: link)]
        )

        let result: SharingResult = try await withCheckedThrowingContinuation { continuation in
            ShareApi.shared.shareDefault(templatable: template) { sharingResult, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let sharingResult {
                    continuation.resume(returning: sharingResult)
                } else {
                    continuation.resume(throwing: ShareError.kakaoTalkUnavailable)
                }
            }
        }
        // shareDefault는 카카오톡으로 넘길 URL만 만들어 준다 — 실제 앱 전환은 직접 연다.
        await UIApplication.shared.open(result.url)
    }

    /// 카드 이미지 URL. 디자인된 배너를 ImageRenderer로 그려 카카오에 1회 업로드하고 URL을 캐시한다
    /// (FeedTemplate은 공개 이미지 URL이 필수. 이후 공유는 캐시된 URL을 재사용해 지연 없음).
    @MainActor
    private static func invitationImageURL() async throws -> URL {
        if let cached = UserDefaults.standard.string(forKey: cachedImageUrlKey),
           let url = URL(string: cached) {
            return url
        }
        guard let image = renderInviteBanner() else { throw ShareError.imageUnavailable }
        let result: ImageUploadResult = try await withCheckedThrowingContinuation { continuation in
            ShareApi.shared.imageUpload(image: image) { uploadResult, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let uploadResult {
                    continuation.resume(returning: uploadResult)
                } else {
                    continuation.resume(throwing: ShareError.imageUnavailable)
                }
            }
        }
        let url = result.infos.original.url
        UserDefaults.standard.set(url.absoluteString, forKey: cachedImageUrlKey)
        return url
    }

    /// 초대 배너 SwiftUI 뷰를 800x400(@2x) 이미지로 렌더한다.
    @MainActor
    private static func renderInviteBanner() -> UIImage? {
        let renderer = ImageRenderer(content: InviteCardImage())
        renderer.scale = 2
        return renderer.uiImage
    }
}

/// 카카오 공유 카드 이미지로 렌더되는 초대 배너. 맨 마스코트 대신 마스코트+문구+브랜드 그라데이션의
/// "초대장" 느낌. 화면에 직접 띄우지 않고 ImageRenderer로만 이미지화한다.
struct InviteCardImage: View {
    var body: some View {
        HStack(spacing: 28) {
            Image("DaramHi")
                .resizable()
                .scaledToFit()
                .frame(width: 210, height: 210)
            VStack(alignment: .leading, spacing: 12) {
                Text("오도독에 초대받았어요")
                    .font(.appFont(.heavy, size: 36))
                    .foregroundStyle(Color.ink800)
                Text("같이 식사 목표 채워요")
                    .font(.appFont(.semibold, size: 23))
                    .foregroundStyle(Color.ink600)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 52)
        .frame(width: 800, height: 400)
        .background(
            LinearGradient(
                colors: [Color.acorn100, Color.cream, Color.sage100],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
