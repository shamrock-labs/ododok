import Foundation
import UIKit
import KakaoSDKShare
import KakaoSDKTemplate

/// 친구 초대를 카카오톡 인앱 공유로 보낸다(링크 복사 아님 — 카카오톡 공유 시트가 직접 뜬다).
/// 마스코트 이미지 + 제목 + 버튼의 FeedTemplate 카드로 보내며, 받은 사람이 버튼을 누르면
/// `code` 파라미터로 앱이 열려 자동 수락 흐름으로 이어진다. 카카오 로그인과 동일한 네이티브 앱키 위에서 동작한다.
enum KakaoInviteSharer {

    enum ShareError: Error {
        case noCode
        case kakaoTalkUnavailable
        case imageUnavailable
    }

    /// 업로드한 카드 이미지 URL 캐시 키. 마스코트는 정적이라 한 번 올리고 재사용한다.
    private static let cachedImageUrlKey = "ChewChewIOS.KakaoInvite.cardImageUrl"

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

    /// 카드 이미지 URL. FeedTemplate은 공개 이미지 URL이 필수라, 마스코트를 카카오에 1회 업로드해
    /// URL을 받고 캐시한다(이후 공유는 캐시된 URL을 재사용해 업로드 지연 없음).
    @MainActor
    private static func invitationImageURL() async throws -> URL {
        if let cached = UserDefaults.standard.string(forKey: cachedImageUrlKey),
           let url = URL(string: cached) {
            return url
        }
        guard let image = UIImage(named: "DaramHi") else { throw ShareError.imageUnavailable }
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
}
