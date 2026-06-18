import Foundation
import UIKit
import KakaoSDKShare
import KakaoSDKTemplate

/// 친구 초대를 카카오톡 인앱 공유로 보낸다(링크 복사 아님 — 카카오톡 공유 시트가 직접 뜬다).
/// 받은 사람이 메시지의 버튼을 누르면 `code` 파라미터로 앱이 열려 자동 수락 흐름으로 이어진다.
/// 카카오 로그인과 동일한 네이티브 앱키(KakaoNativeAppKey) 위에서 동작한다.
enum KakaoInviteSharer {

    enum ShareError: Error {
        case noCode
        case kakaoTalkUnavailable
    }

    /// 초대 코드로 카카오 공유 시트를 띄운다. 성공 시 카카오톡이 열린다.
    @MainActor
    static func share(code: String) async throws {
        guard !code.isEmpty else { throw ShareError.noCode }
        // 카카오톡 미설치 시 공유 시트가 뜨지 않으므로 호출부에서 안내한다.
        guard ShareApi.isKakaoTalkSharingAvailable() else { throw ShareError.kakaoTalkUnavailable }

        // 받은 앱이 code 파라미터로 초대 코드를 수신하도록 iosExecutionParams에 실어 보낸다.
        let link = Link(iosExecutionParams: ["code": code])
        let template = TextTemplate(
            text: "오도독에서 같이 식사 목표를 채워요!",
            link: link,
            buttonTitle: "초대 수락하기"
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
}
