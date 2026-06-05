import ActivityKit
import SwiftUI
import WidgetKit

/// 식사 측정 Live Activity — 잠금화면 배너 + 다이내믹 아일랜드.
/// 평상시엔 경과 시간과 "측정 중"을, 전화로 멈추면 "이어서 측정" 딥링크 버튼을 보여준다.
struct MealLiveActivity: Widget {
    private static let resumeURL = URL(string: "chewchew://resume")!

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MealActivityAttributes.self) { context in
            lockScreen(context)
                .padding(16)
                .activityBackgroundTint(Color(white: 0.97))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("오도독", systemImage: "fork.knife")
                        .font(.caption).foregroundStyle(.brown)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPausedByCall {
                        Link(destination: Self.resumeURL) {
                            Text("이어서 측정").font(.caption.bold())
                        }
                    } else {
                        Text(context.attributes.startedAt, style: .timer)
                            .font(.caption.monospacedDigit())
                            .frame(maxWidth: 64)
                            .multilineTextAlignment(.trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.isPausedByCall
                         ? "통화로 잠시 멈췄어요. 끊고 나서 이어가세요."
                         : "식사 측정 중이에요.")
                        .font(.caption)
                }
            } compactLeading: {
                Image(systemName: context.state.isPausedByCall ? "pause.fill" : "fork.knife")
                    .foregroundStyle(.brown)
            } compactTrailing: {
                if context.state.isPausedByCall {
                    Image(systemName: "phone.down.fill").foregroundStyle(.brown)
                } else {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.caption2.monospacedDigit())
                        .frame(maxWidth: 44)
                }
            } minimal: {
                Image(systemName: context.state.isPausedByCall ? "pause.fill" : "fork.knife")
                    .foregroundStyle(.brown)
            }
            .widgetURL(Self.resumeURL)
        }
    }

    @ViewBuilder
    private func lockScreen(_ context: ActivityViewContext<MealActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: context.state.isPausedByCall ? "pause.circle.fill" : "fork.knife.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.brown)

            VStack(alignment: .leading, spacing: 2) {
                Text("오도독")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if context.state.isPausedByCall {
                    Text("식사 측정이 멈췄어요")
                        .font(.headline)
                    Text("통화가 끝나면 이어서 측정하세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("식사 측정 중")
                        .font(.headline)
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if context.state.isPausedByCall {
                Link(destination: Self.resumeURL) {
                    Text("계속하기")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.brown, in: Capsule())
                }
            }
        }
    }
}
