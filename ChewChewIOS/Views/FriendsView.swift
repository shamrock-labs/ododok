import SwiftUI

struct FriendsView: View {
    @Environment(AppState.self) private var state
    @State private var inviteToastVisible = false
    @State private var toastMessage = ""

    var body: some View {
        VStack(spacing: AppSpacing.homeVertical) {
            header
            inviteCard
            rankingCard
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.cardOuter)
        .padding(.top, AppSpacing.cardOuter)
        .padding(.bottom, AppSpacing.cardOuterBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            if inviteToastVisible {
                Text(toastMessage)
                    .font(.appFont(.boldCaption))
                    .foregroundStyle(Color.textActionInverse)
                    .padding(.horizontal, AppSpacing.toastH)
                    .padding(.vertical, AppSpacing.toastV)
                    .background(Color.textDefault, in: RoundedRectangle(cornerRadius: AppRadius.elementLarge))
                    .softShadow(.lg)
                    .padding(.bottom, AppSpacing.overlayBottom)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .task {
            await state.refreshFriendArea()
        }
    }

    // MARK: Header

    private var header: some View {
        AppHeaderView(eyebrow: "함께 먹는 리듬", title: "친구", subtitle: "초대와 랭킹을 한 곳에서 준비해요") {
            HeaderMetricPill(icon: .people, value: "준비중", tint: .sage600)
        }
    }

    // MARK: Invite

    private var inviteCard: some View {
        AppCard(padding: AppSpacing.five, elevation: .medium) {
            VStack(spacing: AppSpacing.reportCell) {
            // 카카오 초대를 가장 크게(주 액션). 카카오 공식 옐로우 + 어두운 텍스트.
            Button {
                Task { await shareInvite() }
            } label: {
                HStack(spacing: AppSpacing.two) {
                    Image(systemName: "message.fill")
                        .font(.appFont(.boldBodyLarge))
                    Text("카카오톡으로 초대하기")
                        .font(.appFont(.heavyHeadline))
                }
                .foregroundStyle(Color.textDefault)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.homeVertical)
                .background(Color.kakaoYellow, in: RoundedRectangle(cornerRadius: AppRadius.container))
            }
            .buttonStyle(PressableButtonStyle())
            .softShadow(.pill)

            // 내 초대 코드는 작게 아래에. 영구 단일 코드라 "새로고침"은 두지 않고, 실패 시에만 다시 시도.
            inviteCodeLine
            }
        }
    }

    /// 내 초대 코드(작게). 로딩 중 미니 스피너, 3회 재시도까지 실패하면 "다시 시도".
    private var inviteCodeLine: some View {
        HStack(spacing: AppSpacing.oneHalf) {
            Text("내 초대 코드")
                .font(.appFont(.semiboldCaption))
                .foregroundStyle(Color.textSubtle)
            if let code = state.friendInviteCode {
                Text(code)
                    .font(.appFont(.boldCallout))
                    .foregroundStyle(Color.textMuted)
            } else if state.friendAreaLoadState == .failed {
                Button("다시 시도") {
                    Task { await state.refreshFriendArea() }
                }
                .font(.appFont(.boldCaption))
                .foregroundStyle(Color.statusSuccess)
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var rankingCard: some View {
        AppCard(padding: AppSpacing.dialogH, radius: AppRadius.page, elevation: .medium) {
            VStack(alignment: .leading, spacing: AppSpacing.reportCell) {
            Text("친구 랭킹")
                .font(.appFont(.heavyHeadlineLarge))
                .foregroundStyle(Color.textDefault)
            if state.friendAreaLoadState == .loading && state.friendRankings.isEmpty {
                // 첫 로딩(재시도 포함) 중엔 "없음" 대신 스피너.
                ProgressView()
                    .controlSize(.small)
            } else if state.friendAreaLoadState == .failed {
                // 실패 시엔 직전 랭킹이 남아 있어도 성공처럼 보여주지 않는다(stale 노출 방지).
                Text("잠시 후 다시 시도해 주세요")
                    .font(.appFont(.semiboldLabel))
                    .foregroundStyle(Color.textSubtle)
            } else if state.friendRankings.isEmpty {
                Text("아직 랭킹이 없어요. 친구를 초대해 보세요.")
                    .font(.appFont(.semiboldLabel))
                    .foregroundStyle(Color.textSubtle)
            } else {
                VStack(spacing: AppSpacing.one) {
                    ForEach(Array(state.friendRankings.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: AppSpacing.inner) {
                            Text("\(index + 1)")
                                .font(.appFont(.heavyLabel))
                                .foregroundStyle(row.me ? Color.statusSuccess : Color.textSubtle)
                                .frame(minWidth: AppSize.iconSmall)
                            Text(rankingName(row))
                                .font(.appFont(.boldLabel))
                                .foregroundStyle(Color.textDefault)
                                .lineLimit(1)
                            Spacer()
                            Text("\(row.points) 도토리")
                                .font(.appFont(.semiboldLabel))
                                .foregroundStyle(Color.statusSuccess)
                        }
                        .padding(.horizontal, AppSpacing.three)
                        .padding(.vertical, AppRadius.iconContainer)
                        // 내 행은 은은한 배경 틴트로 자연스럽게 강조.
                        .background(
                            row.me ? Color.statusSuccessMuted : Color.clear,
                            in: RoundedRectangle(cornerRadius: AppSpacing.three)
                        )
                    }
                }
            }
            }
        }
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
