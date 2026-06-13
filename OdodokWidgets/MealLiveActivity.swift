import ActivityKit
import SwiftUI
import WidgetKit

/// 식사 측정 Live Activity — 잠금화면 배너 + 다이내믹 아일랜드.
/// 잠금화면은 앱 알림 카드 디자인(화이트 카드 + 다람이 아바타 + 브라운 버튼)에 맞춘다.
/// 평상시엔 경과 시간과 "측정 중"을, 전화로 멈추면 "그만하기 / 계속하기"를 보여준다.
struct MealLiveActivity: Widget {
    private static let resumeURL = URL(string: "chewchew://resume")!
    private static let stopURL = URL(string: "chewchew://stop")!

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MealActivityAttributes.self) { context in
            // 잠금화면 기본 머티리얼은 다크 모드에서 텍스트 대비가 흔들릴 수 있다.
            // 끼니 푸시 알림처럼 반투명 크림 카드 위에 고정 팔레트를 올려 양쪽 모드 모두 읽히게 한다.
            lockScreen(context)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.94),
                                    Color.mealGlassBase.opacity(0.94),
                                    Color.mealGlassWarmth.opacity(0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.62), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 8)
                .padding(.horizontal, 2)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(Color.mealBrown)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image("DaramAvatar")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .clipShape(Circle())
                        Text("오도독")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.mealIslandAccent)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.isPausedByCall ? "측정이 잠시 멈췄어요" : "식사 측정 중")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPausedByCall {
                        Link(destination: Self.resumeURL) {
                            Text("계속")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.mealIslandAccent)
                        }
                    } else {
                        Text(context.attributes.startedAt, style: .timer)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(maxWidth: 64)
                            .multilineTextAlignment(.trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        Text(context.state.isPausedByCall
                             ? "이어가거나 오늘 식사를 마무리할 수 있어요."
                             : "천천히 맛있게 드세요.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if context.state.isPausedByCall {
                            dynamicIslandPill("그만", url: Self.stopURL, filled: false)
                            dynamicIslandPill("계속", url: Self.resumeURL, filled: true)
                        } else {
                            dynamicIslandPill("그만하기", url: Self.stopURL, filled: false)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPausedByCall ? "pause.fill" : "fork.knife")
                    .foregroundStyle(Color.mealIslandAccent)
            } compactTrailing: {
                if context.state.isPausedByCall {
                    Image(systemName: "phone.down.fill").foregroundStyle(Color.mealIslandAccent)
                } else {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.caption2.monospacedDigit())
                        .frame(maxWidth: 44)
                }
            } minimal: {
                Image(systemName: context.state.isPausedByCall ? "pause.fill" : "fork.knife")
                    .foregroundStyle(Color.mealIslandAccent)
            }
            .keylineTint(Color.mealIslandAccent)
            .widgetURL(Self.resumeURL)
        }
    }

    // MARK: - Lock screen card (앱 알림 카드 디자인)

    @ViewBuilder
    private func lockScreen(_ context: ActivityViewContext<MealActivityAttributes>) -> some View {
        let paused = context.state.isPausedByCall
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("오도독")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.mealBrown)
                    Spacer(minLength: 4)
                    if paused {
                        Text("지금")
                            .font(.caption2)
                            .foregroundStyle(Color.mealFaint)
                    } else {
                        Text(context.attributes.startedAt, style: .timer)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.mealFaint)
                            .frame(maxWidth: 56, alignment: .trailing)
                    }
                }

                Text(paused ? "식사 측정이 중단되었어요!" : "식사 측정 중이에요")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(Color.mealTitle)

                Text(paused
                     ? "방금 알림이나 전화가 왔나요? 식사 기록을 이어서 계속 진행할까요?"
                     : "다람이가 꼭꼭 씹는 걸 지켜보고 있어요. 천천히 맛있게 드세요.")
                    .font(.footnote)
                    .foregroundStyle(Color.mealBody)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if paused {
                        pillButton("그만하기", url: Self.stopURL, filled: false)
                        pillButton("계속하기", url: Self.resumeURL, filled: true)
                    } else {
                        pillButton("그만하기", url: Self.stopURL, filled: false)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    /// 잠금화면 카드용 알약 버튼. filled=브라운(주요 액션), 아니면 연회색 칩.
    /// Live Activity의 Link는 탭 시 앱을 열어 딥링크(stop/resume)를 수행한다.
    private func pillButton(_ title: String, url: URL, filled: Bool) -> some View {
        Link(destination: url) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(filled ? Color.white : Color.mealBody)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(filled ? Color.mealBrown : Color.mealChip.opacity(0.78), in: Capsule())
                .overlay {
                    Capsule().stroke(Color.white.opacity(filled ? 0.16 : 0.34), lineWidth: 1)
                }
        }
    }

    private func dynamicIslandPill(_ title: String, url: URL, filled: Bool) -> some View {
        Link(destination: url) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(filled ? Color.black : Color.white.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(filled ? Color.mealBrown : Color.white.opacity(0.14), in: Capsule())
        }
    }

    private var avatar: some View {
        Image("DaramAvatar")
            .resizable()
            .scaledToFit()
            .padding(6)
            .frame(width: 48, height: 48)
            .background(Color.mealAvatarBg.opacity(0.86), in: Circle())
            .overlay {
                Circle().stroke(Color.white.opacity(0.42), lineWidth: 1)
            }
    }
}

private extension Color {
    /// 알림 카드 팔레트. 위젯 타겟엔 Colors.swift가 없어 인라인으로 두되 앱 ink/acorn 값과 정렬한다.
    /// 텍스트는 시스템 외관과 무관하게 고정 색이라 반투명 머티리얼 위에서도 또렷.
    static let mealGlassBase = Color(red: 253/255, green: 248/255, blue: 239/255)
    static let mealGlassWarmth = Color(red: 1, green: 251/255, blue: 244/255)
    static let mealAvatarBg = Color(red: 251/255, green: 243/255, blue: 232/255)  // acorn50
    static let mealTitle = Color(red: 45/255, green: 36/255, blue: 24/255)        // ink800
    static let mealBody = Color(red: 92/255, green: 79/255, blue: 62/255)         // ink600
    static let mealFaint = Color(red: 140/255, green: 123/255, blue: 102/255)     // ink400
    static let mealBrown = Color(red: 156/255, green: 110/255, blue: 71/255)      // acorn600
    static let mealIslandAccent = Color(red: 214/255, green: 171/255, blue: 126/255)
    static let mealChip = Color(red: 242/255, green: 237/255, blue: 229/255)      // ink100
}
