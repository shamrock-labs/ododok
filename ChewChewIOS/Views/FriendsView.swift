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

    private var inviteCard: some View {
        VStack(spacing: 14) {
            // 카카오 초대를 가장 크게(주 액션). 카카오 공식 옐로우 + 어두운 텍스트.
            Button {
                Task { await shareInvite() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "message.fill")
                        .font(.appFont(.bold, size: 16))
                    Text("카카오톡으로 초대하기")
                        .font(.appFont(.heavy, size: 17))
                }
                .foregroundStyle(Color.ink800)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.kakaoYellow, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(PressableButtonStyle())
            .softShadow(.pill)

            // 내 초대 코드는 작게 아래에. 영구 단일 코드라 "새로고침"은 두지 않고, 실패 시에만 다시 시도.
            inviteCodeLine
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .neuoShadow(.md)
    }

    /// 내 초대 코드(작게). 로딩 중 미니 스피너, 3회 재시도까지 실패하면 "다시 시도".
    private var inviteCodeLine: some View {
        HStack(spacing: 6) {
            Text("내 초대 코드")
                .font(.appFont(.semibold, size: 12))
                .foregroundStyle(Color.ink400)
            if let code = state.friendInviteCode {
                Text(code)
                    .font(.appFont(.bold, size: 13))
                    .foregroundStyle(Color.ink600)
            } else if state.friendAreaLoadState == .failed {
                Button("다시 시도") {
                    Task { await state.refreshFriendArea() }
                }
                .font(.appFont(.bold, size: 12))
                .foregroundStyle(Color.sage600)
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .frame(maxWidth: .infinity)
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
                VStack(spacing: 4) {
                    ForEach(Array(state.friendRankings.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.appFont(.heavy, size: 14))
                                .foregroundStyle(row.me ? Color.sage600 : Color.ink400)
                                .frame(minWidth: 18)
                            Text(rankingName(row))
                                .font(.appFont(.bold, size: 14))
                                .foregroundStyle(Color.ink800)
                                .lineLimit(1)
                            Spacer()
                            Text("\(row.points) 도토리")
                                .font(.appFont(.semibold, size: 14))
                                .foregroundStyle(Color.sage600)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        // 내 행은 은은한 배경 틴트로 자연스럽게 강조.
                        .background(
                            row.me ? Color.sage50 : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
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

    /// 랭킹 행 표시 이름. 내 행은 내 닉네임(없으면 "나"), 친구는 서버 표시 이름(없으면 "친구").
    private func rankingName(_ row: FriendRankingDTO) -> String {
        if row.me {
            return state.displayName ?? row.name ?? "나"
        }
        return row.name ?? "친구"
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
            try await KakaoInviteSharer.share(code: code)
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
