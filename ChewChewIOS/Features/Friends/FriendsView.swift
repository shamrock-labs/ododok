import SwiftUI

struct FriendsView: View {
    @Environment(AppState.self) private var state
    @State private var toast: AppToastMessage?

    @MainActor
    private var store: FriendsStore {
        state.friends
    }

    var body: some View {
        VStack(spacing: AppSpacing.verticalLoose) {
            header
            inviteCard
            rankingCard
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.cardOuter)
        .padding(.top, AppSpacing.cardOuter)
        .padding(.bottom, AppSpacing.cardOuterBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .appToast($toast)
        .task {
            await store.load()
        }
    }

    // MARK: Header

    private var header: some View {
        AppHeaderView(eyebrow: "함께 먹는 리듬", title: "친구", subtitle: "초대와 랭킹을 한 곳에서 확인해요")
    }

    // MARK: Invite

    private var inviteCard: some View {
        AppCard(padding: AppSpacing.five, elevation: .flat) {
            // 카카오 초대 단일 액션. 초대 코드 텍스트 노출은 v1.1에서 제거 —
            // 코드 미로딩/실패는 shareInvite()의 토스트가 안내한다.
            AppActionButton(
                action: {
                    Task { await shareInvite() }
                },
                foreground: Color.textDefault,
                background: AnyShapeStyle(Color.kakaoYellow),
                radius: AppRadius.container,
                verticalPadding: AppSpacing.verticalLoose,
                label: {
                    HStack(spacing: AppSpacing.two) {
                        Image(systemName: "message.fill")
                            .font(.appFont(.boldBodyLarge))
                        Text("카카오톡으로 초대하기")
                            .font(.appFont(.heavyHeadline))
                    }
                }
            )
        }
    }

    private var rankingCard: some View {
        AppCard(padding: AppSpacing.dialogH, radius: AppRadius.page, elevation: .flat) {
            VStack(alignment: .leading, spacing: AppSpacing.cell) {
            Text("친구 랭킹")
                .font(.appFont(.heavyHeadlineLarge))
                .foregroundStyle(Color.textDefault)
            if store.loadState == .loading && store.rankings.isEmpty {
                // 첫 로딩(재시도 포함) 중엔 "없음" 대신 스피너.
                ProgressView()
                    .controlSize(.small)
            } else if store.loadState == .failed {
                // 실패 시엔 직전 랭킹이 남아 있어도 성공처럼 보여주지 않는다(stale 노출 방지).
                Text("잠시 후 다시 시도해 주세요")
                    .font(.appFont(.semiboldLabel))
                    .foregroundStyle(Color.textSubtle)
            } else if store.rankings.isEmpty {
                Text("아직 랭킹이 없어요. 친구를 초대해 보세요.")
                    .font(.appFont(.semiboldLabel))
                    .foregroundStyle(Color.textSubtle)
            } else {
                VStack(spacing: AppSpacing.one) {
                    ForEach(Array(store.rankings.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: AppSpacing.inner) {
                            Text("\(index + 1)")
                                .font(.appFont(.heavyLabel))
                                .foregroundStyle(row.me ? Color.statusSuccess : Color.textSubtle)
                                .frame(minWidth: AppSize.iconSmall)
                            Text(store.displayName(for: row))
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

    /// 카카오톡 인앱 공유로 초대를 보낸다(링크 복사 아님 — 카카오톡 공유 시트가 직접 뜬다).
    /// 코드 미로딩/카톡 미설치는 토스트로 안내한다.
    @MainActor
    private func shareInvite() async {
        guard let code = store.inviteCode, !code.isEmpty else {
            toast = AppToastMessage("초대 코드를 불러오는 중이에요", kind: .info)
            return
        }
        do {
            try await KakaoInviteSharer.share(code: code)
        } catch KakaoInviteSharer.ShareError.kakaoTalkUnavailable {
            toast = AppToastMessage("카카오톡이 설치되어 있지 않아요", kind: .warning)
        } catch {
            toast = AppToastMessage("초대 공유에 실패했어요", kind: .warning)
        }
    }
}
