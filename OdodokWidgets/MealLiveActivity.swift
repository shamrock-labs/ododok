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
            // 시스템 기본 잠금화면 배경을 그대로 쓴다 — 라이트=흰/다크=검정으로 자동 적응(교통앱 등과 동일).
            // 커스텀 불투명 배경(머티리얼·고정 크림)을 깔면 그 적응을 못 받아 한쪽 모드에서 글자가 묻힌다.
            // 그래서 배경은 시스템에 맡기고, 글자·요소만 적응형 색(.primary/.secondary)으로 둔다.
            lockScreen(context)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image("RealDaram")
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
                        // 통화 종료 후에만 계속 노출, 통화 중엔 비움
                        if !context.state.callActive {
                            Link(destination: Self.resumeURL) {
                                Text("계속")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.mealIslandAccent)
                            }
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
                        Text(!context.state.isPausedByCall
                             ? "천천히 맛있게 드세요."
                             : (context.state.callActive
                                ? "통화가 끝나면 이어집니다."
                                : "이어가거나 오늘 식사를 마무리할 수 있어요."))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if context.state.isPausedByCall {
                            // 통화 중엔 버튼 없음, 종료 후 그만/계속
                            if !context.state.callActive {
                                dynamicIslandPill("그만", url: Self.stopURL, filled: false)
                                dynamicIslandPill("계속", url: Self.resumeURL, filled: true)
                            }
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
        let callActive = paused && context.state.callActive   // 통화 진행 중 — 버튼 없이 "멈춤"만
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("오도독")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
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

                Text(Self.lockTitle(paused: paused, callActive: callActive))
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(Color.mealTitle)

                Text(Self.lockBody(paused: paused, callActive: callActive))
                    .font(.footnote)
                    .foregroundStyle(Color.mealBody)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                // 측정 중=그만하기 / 통화 중=버튼 없음 / 통화 종료=그만하기+계속하기
                if !callActive {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        pillButton("그만하기", url: Self.stopURL, filled: false)
                        if paused {
                            pillButton("계속하기", url: Self.resumeURL, filled: true)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    /// 잠금화면 제목 — 측정 중 / 통화 중 멈춤 / 통화 종료.
    private static func lockTitle(paused: Bool, callActive: Bool) -> String {
        if !paused { return "식사 측정 중이에요" }
        return callActive ? "측정이 멈췄어요" : "식사 측정이 중단되었어요!"
    }

    /// 잠금화면 본문 — 통화 중엔 "끝나면 이어진다"만, 종료 후엔 이어가기 안내.
    private static func lockBody(paused: Bool, callActive: Bool) -> String {
        if !paused { return "다람이가 꼭꼭 씹는 걸 지켜보고 있어요. 천천히 맛있게 드세요." }
        return callActive
            ? "통화가 끝나면 이어서 측정할 수 있어요."
            : "방금 알림이나 전화가 왔나요? 식사 기록을 이어서 계속 진행할까요?"
    }

    /// 잠금화면 카드용 알약 버튼(PillButton 래퍼). 탭 시 앱을 열어 딥링크(stop/resume) 수행.
    private func pillButton(_ title: String, url: URL, filled: Bool) -> some View {
        PillButton(title: title, url: url, filled: filled)
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
        // 배경 박스·테두리 없이 다람이(앱 아이콘 마스코트)만 — 라이트/다크 카드 공통으로 자연스럽게 얹힌다.
        Image("RealDaram")
            .resizable()
            .scaledToFit()
            .frame(width: 48, height: 48)
    }
}

/// 잠금화면 알약 버튼. colorScheme을 직접 읽어 비채움(그만하기) 버튼 색을 모드별로 다르게 둔다 —
/// 라이트=따뜻한 브라운(연한 채움), 다크=회색 시맨틱(다크에선 회색이 더 자연스러움). 테두리 없음.
/// filled(계속하기)는 양쪽 모두 솔리드 브라운 + 흰 글자.
private struct PillButton: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let url: URL
    let filled: Bool

    var body: some View {
        Link(destination: url) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(textColor)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(fill, in: Capsule())
        }
    }

    private var textColor: Color {
        if filled { return .white }
        return scheme == .dark ? Color.mealBody : Color.mealBrown
    }
    private var fill: Color {
        if filled { return Color.mealBrown }
        return scheme == .dark ? Color.primary.opacity(0.15) : Color.mealBrown.opacity(0.14)
    }
}

private extension Color {
    /// 잠금화면 카드 팔레트. 배경이 시스템 기본(라이트=흰/다크=검정 자동 적응)이라, 글자·칩도 시스템
    /// 시맨틱 색을 써서 같이 적응시킨다(라이트=어두운 글자 / 다크=밝은 글자). 채워진 버튼·아일랜드만 고정 액센트.
    static let mealTitle = Color.primary
    static let mealBody = Color.primary.opacity(0.80)
    static let mealFaint = Color.secondary
    static let mealBrown = Color(red: 156/255, green: 110/255, blue: 71/255)      // acorn600 — 버튼 액센트(솔리드/아웃라인, 양쪽 OK)
    static let mealIslandAccent = Color(red: 214/255, green: 171/255, blue: 126/255)  // 다이내믹 아일랜드(항상 다크)
}
