import SwiftUI

struct FriendsView: View {
    @Environment(AppState.self) private var state
    @State private var inviteToastVisible = false
    @State private var toastMessage = ""

    var body: some View {
        VStack(spacing: 18) {
            header
            inviteCard
            rankingCard
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            if inviteToastVisible {
                Text(toastMessage)
                    .font(.appFont(.bold, size: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.ink800, in: RoundedRectangle(cornerRadius: 16))
                    .softShadow(.lg)
                    .padding(.bottom, 110)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .task {
            await state.refreshFriendArea()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("친구")
                .font(.appFont(.heavy, size: 22))
                .foregroundStyle(Color.ink800)
            Spacer()
        }
    }

    // MARK: Invite

    /// 내 초대 코드 표시. 로딩(재시도 포함) 중엔 스피너, 3회까지 모두 실패한 뒤에만 안내 문구를 보여준다.
    @ViewBuilder
    private var inviteCodeView: some View {
        if let code = state.friendInviteCode {
            Text(code)
                .font(.appFont(.heavy, size: 18))
                .foregroundStyle(Color.ink800)
        } else if state.friendAreaLoadState == .failed {
            Text("잠시 후 다시 시도해 주세요")
                .font(.appFont(.semibold, size: 14))
                .foregroundStyle(Color.ink400)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    private var inviteCard: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("내 초대 코드")
                    .font(.appFont(.bold, size: 12))
                    .foregroundStyle(Color.ink600)
                HStack {
                    inviteCodeView
                    Spacer()
                    Button("새로고침") {
                        Task { await state.refreshFriendArea() }
                    }
                    .font(.appFont(.bold, size: 13))
                    .foregroundStyle(Color.sage600)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.cream, in: RoundedRectangle(cornerRadius: 14))
            }

            Button {
                Task { await shareInvite() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paperplane.fill")
                        .font(.appFont(.bold, size: 15))
                    Text("카카오톡으로 초대하기")
                        .font(.appFont(.bold, size: 16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.sage600, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(PressableButtonStyle())
            .softShadow(.pill)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .neuoShadow(.md)
    }

    private var rankingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("친구 랭킹")
                .font(.appFont(.heavy, size: 18))
                .foregroundStyle(Color.ink800)
            if state.friendAreaLoadState == .loading && state.friendRankings.isEmpty {
                // 첫 로딩(재시도 포함) 중엔 "없음" 대신 스피너.
                ProgressView()
                    .controlSize(.small)
            } else if state.friendAreaLoadState == .failed {
                // 실패 시엔 직전 랭킹이 남아 있어도 성공처럼 보여주지 않는다(stale 노출 방지).
                Text("잠시 후 다시 시도해 주세요")
                    .font(.appFont(.semibold, size: 14))
                    .foregroundStyle(Color.ink400)
            } else if state.friendRankings.isEmpty {
                Text("아직 랭킹이 없어요. 친구를 초대해 보세요.")
                    .font(.appFont(.semibold, size: 14))
                    .foregroundStyle(Color.ink400)
            } else {
                ForEach(Array(state.friendRankings.enumerated()), id: \.element.id) { index, row in
                    HStack {
                        Text(row.me ? "나" : "친구 \(index + 1)")
                            .font(.appFont(.bold, size: 14))
                            .foregroundStyle(Color.ink800)
                        Spacer()
                        Text("\(row.points) 도토리")
                            .font(.appFont(.semibold, size: 14))
                            .foregroundStyle(Color.sage600)
                    }
                    .padding(.vertical, 10)
                    if index + 1 < state.friendRankings.count {
                        Divider().overlay(Color.ink100)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28))
        .neuoShadow(.md)
    }

    /// 카카오톡 인앱 공유로 초대를 보낸다(링크 복사 아님 — 카카오톡 공유 시트가 직접 뜬다).
    /// 코드 미로딩/카톡 미설치는 토스트로 안내한다.
    @MainActor
    private func shareInvite() async {
        guard let code = state.friendInviteCode, !code.isEmpty else {
            showToast("초대 코드를 불러오는 중이에요")
            return
        }
        do {
            try await KakaoInviteSharer.share(code: code, deepLink: state.friendInviteDeepLink)
        } catch KakaoInviteSharer.ShareError.kakaoTalkUnavailable {
            showToast("카카오톡이 설치되어 있지 않아요")
        } catch {
            showToast("초대 공유에 실패했어요")
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation { inviteToastVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { inviteToastVisible = false }
        }
    }
}
