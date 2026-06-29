import SwiftUI

/// 식사 후 분석 리포트 카드의 표시 모델. `ChewingSessionDTO` → 이 모델로 변환하는
/// 매퍼는 아래 extension에서 노출. UI 컴포넌트가 DTO 변경에 직접 결합되지 않도록 분리.
struct ReportCardModel: Equatable {
    /// 분석 점수 0~100. 씹기 점수 섹션에 노출하고 mood/grade 산출에도 쓴다.
    let score: Int
    /// 내부 분석 등급. 화면에는 씹기 점수 + 권장 기준 대비 분석을 노출한다.
    let grade: Grade
    /// 4대 지표.
    let chewCount: Int
    let totalDurationSec: Double
    let chewsPerMinute: Double
    /// 씹기 집중 비율 0~1 (`chewingFraction`). 리듬 요소 점수의 근거 값.
    let chewingFraction: Double
    /// 씹기·쉬기 구간 바. 한 끼 중 실제 씹은 시간 / 쉰 시간(초).
    let chewingSeconds: Double
    let restSeconds: Double
    /// 내부 4요소 분해 (각 0~100). 씹기 점수 섹션에서 4축 미니바로 노출한다.
    let speedScore: Int
    let rhythmScore: Int
    let continuityScore: Int
    let lengthScore: Int
    /// 한 줄 캡션. nil이면 기본 멘트 fallback.
    let caption: String?
    /// 다람이 일러스트(점수 등급에서 매핑). 헤더 표정으로 사용.
    let mood: Mood
    /// 식사 종료 시각 — 헤더 날짜 라벨에 사용.
    let endedAt: Date

    enum Grade {
        case good, soso, bad

        var label: String {
            switch self {
            case .good: "잘 씹었어요"
            case .soso: "조금 더 천천히"
            case .bad:  "다음엔 천천히"
            }
        }
    }
}

/// 점수 카운트업 값. progress 0→1 동안 0→target 선형, 0~1 밖은 클램프.
/// 씹기 점수 섹션의 카운트업 애니메이션에 쓰이고 `ReportCardModelTests`가 가드한다.
func scoreCountUpValue(progress: Double, target: Int) -> Int {
    let clamped = min(max(progress, 0), 1)
    return Int((clamped * Double(target)).rounded())
}

/// 식사 후 분석 리포트 카드. 식사 종료 직후 sheet/overlay 표시와 캘린더에서 과거 세션
/// 재현 양쪽에서 동일하게 사용된다. 1080×1920 PNG 공유도 같은 View를 ImageRenderer로 렌더.
///
/// `onDeepReport`가 주어지면 하단에 [심층 분석 보기] CTA(REQ-17 진입)를 노출한다.
/// 기본 nil이라 PNG 공유 렌더처럼 CTA가 불필요한 호출부는 그대로 둔다.
struct ReportCardView: View {
    let model: ReportCardModel
    var onDeepReport: (() -> Void)? = nil
    /// PNG(ImageRenderer) 정적 렌더 여부. onAppear가 안 불리는 렌더 경로에서도 점수가
    /// 카운트업 0이 아니라 완성값으로 찍히게 한다. 기본 false(라이브 카운트업).
    var rendersStatically: Bool = false

    @State private var scoreProgress: Double = 0
    @State private var showScoreGuide = false

    var body: some View {
        VStack(spacing: 18) {
            header
            sectionDivider
            scoreSection
            sectionDivider
            recommendedSection
            sectionDivider
            chewRestSection
            if onDeepReport != nil {
                sectionDivider
                deepReportCTA
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 24))
        .sheet(isPresented: $showScoreGuide) {
            ScoreGuideView()
        }
    }

    /// 섹션 사이 실선 구분선(배경 카드 대신). 점선은 섹션 안 영역 구분에만 따로 쓴다.
    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerDateLabel)
                    .font(.appFont(.semibold, size: 13))
                    .foregroundStyle(Color.textSecondary)
                Text("식사 리포트")
                    .font(.appFont(.display))
                    .foregroundStyle(Color.textPrimary)
            }
            Spacer()
        }
    }

    // MARK: - 씹기 점수 (SessionScore 노출)

    /// 내부에서 계산만 하고 버리던 0~100 점수 + 4축(속도·리듬·연속·길이)을 실제로 노출한다.
    /// 흐리멍덩한 형용사 배지의 정량 근거가 된다.
    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("씹기 점수")
                    .font(.appFont(.heavy, size: 15))
                    .foregroundStyle(Color.textPrimary)
                if !rendersStatically {
                    Button { showScoreGuide = true } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("씹기 점수 설명 보기")
                }
                Spacer(minLength: 0)
                Text("\(scoreCountUpValue(progress: rendersStatically ? 1 : scoreProgress, target: model.score))")
                    .font(.appFont(.heavy, size: 28))
                    .foregroundStyle(scoreColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("/ 100")
                    .font(.appFont(.bold, size: 12))
                    .foregroundStyle(Color.textTertiary)
            }
            // 라벨은 실제 측정값과 1:1로 맞춘다(점수 4축 = 권장 4지표와 동일 대상):
            // speed=분당 속도, rhythm=씹은 시간 비율, continuity=총 저작 횟수, length=식사 시간.
            VStack(spacing: 8) {
                scoreAxisRow(label: "속도", value: model.speedScore)
                scoreAxisRow(label: "비율", value: model.rhythmScore)
                scoreAxisRow(label: "횟수", value: model.continuityScore)
                scoreAxisRow(label: "시간", value: model.lengthScore)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { scoreProgress = 1 }
        }
    }

    private func scoreAxisRow(label: String, value: Int) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.appFont(.bold, size: 12))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 28, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.hairline)
                    Capsule().fill(scoreColor.opacity(0.85))
                        .frame(width: max(6, geo.size.width * CGFloat(max(0, min(100, value))) / 100))
                }
            }
            .frame(height: 8)
            Text("\(value)")
                .font(.appFont(.heavy, size: 12))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
                .frame(width: 26, alignment: .trailing)
        }
    }

    private var scoreColor: Color {
        switch model.grade {
        case .good: Color.accentGood
        case .soso: Color.accentFocus
        case .bad:  Color.accentWarn
        }
    }

    /// 권장 기준과 비교 — 요약 헤더 + 4지표를 한 섹션에서 보여준다.
    /// 이전엔 "권장 기준 대비"(요약)와 "권장 기준 대비 세부"(그리드) 두 섹션으로 제목·지표가
    /// 중복됐다. 단일 헤더 + 4지표 그리드로 합쳐 워딩 중복을 없앤다.
    private var recommendedSection: some View {
        let summary = recommendedComparisonSummary
        return VStack(alignment: .leading, spacing: 16) {
            // 헤더 — "권장 기준보다 ~~한 식사였어요" 한 줄만(배지 제거). 색은 카드 배경으로만 준다(플랫).
            Text(summary.title)
                .font(.appFont(.heavy, size: 19))
                .foregroundStyle(Color.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                spacing: 18
            ) {
                recommendedComparisonCell(
                    label: "저작 횟수",
                    current: "약 \(model.chewCount.koLocale)회",
                    recommended: "권장 \(RecommendedBaseline.chewCount.koLocale)회",
                    delta: signedDelta(model.chewCount - RecommendedBaseline.chewCount, suffix: "회"),
                    // 풀스케일 = 권장 기준의 ±50%. 네 지표가 동일한 상대 논리로 막대를 채운다.
                    ratio: Double(model.chewCount - RecommendedBaseline.chewCount) / (Double(RecommendedBaseline.chewCount) * 0.5),
                    color: .acorn700
                )
                recommendedComparisonCell(
                    label: "식사 시간",
                    current: formatDurationShort(model.totalDurationSec),
                    recommended: "권장 \(formatDurationShort(RecommendedBaseline.durationSec))",
                    delta: signedDelta(durationDeltaMinutes, suffix: "분"),
                    ratio: Double(durationDeltaMinutes) / (RecommendedBaseline.durationSec / 60 * 0.5),
                    color: .sage600
                )
                recommendedComparisonCell(
                    label: "식사 속도",
                    current: "약 \(Int(model.chewsPerMinute.rounded()))회/분",
                    recommended: "권장 \(Int(RecommendedBaseline.chewsPerMinute))회/분",
                    delta: signedDelta(Int((model.chewsPerMinute - RecommendedBaseline.chewsPerMinute).rounded()), suffix: "회/분"),
                    ratio: (model.chewsPerMinute - RecommendedBaseline.chewsPerMinute) / (RecommendedBaseline.chewsPerMinute * 0.5),
                    color: .blush500
                )
                recommendedComparisonCell(
                    label: "씹기 비율",
                    current: "\(Int((model.chewingFraction * 100).rounded()))%",
                    recommended: "권장 \(Int(RecommendedBaseline.chewingFraction * 100))%",
                    delta: signedDelta(chewingFocusDeltaPercent, suffix: "%"),
                    ratio: Double(chewingFocusDeltaPercent) / (RecommendedBaseline.chewingFraction * 100 * 0.5),
                    color: .butter600
                )
            }
        }
        // 섹션 배경 제거 — 섹션 구분은 body의 실선이 담당한다(내부 헤더↔지표 점선은 유지).
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recommendedComparisonCell(
        label: String,
        current: String,
        recommended: String,
        delta: String,
        ratio: Double,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.appFont(.semibold, size: 13))
                    .foregroundStyle(Color.textSecondary)
                Spacer(minLength: 0)
                Text(delta)
                    .font(.appFont(.heavy, size: 11))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.12), in: Capsule())
            }
            Text(current)
                .font(.appFont(.heavy, size: 20))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .monospacedDigit()
            RecommendedDeltaBar(ratio: ratio, color: color)
                .frame(height: 12)
            Text(recommended)
                .font(.appFont(.semibold, size: 13))
                .foregroundStyle(Color.textSecondary.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var coachPanel: some View {
        let summary = recommendedComparisonSummary
        return HStack(spacing: 12) {
            Image(summary.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .background(Color.butter100.opacity(0.7), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(coachTitle)
                    .font(.appFont(.heavy, size: 15))
                    .foregroundStyle(Color.textPrimary)
                Text(coachMessage)
                    .font(.appFont(.semibold, size: 13))
                    .foregroundStyle(Color.textSecondary)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.sage50.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.sage100, lineWidth: 1)
        )
    }

    // MARK: - 씹기 · 쉬기 구간 바

    private var chewRestSection: some View {
        let total = max(0.001, model.chewingSeconds + model.restSeconds)
        let chewFrac = CGFloat(model.chewingSeconds / total)
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("씹기 · 쉬기 구간")
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(Color.sage500)
                        .frame(width: max(0, geo.size.width * chewFrac - 1))
                    Rectangle().fill(Color.acorn200)
                }
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .frame(height: 14)
            HStack(spacing: 16) {
                legendDot(color: .sage500, label: "씹기 \(formatDurationShort(model.chewingSeconds))")
                legendDot(color: .acorn200, label: "쉬기 \(formatDurationShort(model.restSeconds))")
                Spacer(minLength: 0)
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.appFont(.semibold, size: 13))
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var captionSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "quote.opening")
                .font(.appFont(.bold, size: 13))
                .foregroundStyle(Color.acorn300)
            Text(model.caption ?? "오늘 한 끼 잘 먹었어요.")
                .font(.appFont(.semibold, size: 15))
                .foregroundStyle(Color.textSecondary)
                .lineSpacing(3)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.acorn50.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    private var deepReportCTA: some View {
        Button(action: { onDeepReport?() }) {
            HStack(spacing: 8) {
                Text("심층 분석 보기")
                    .font(.appFont(.bold, size: 14))
                    .foregroundStyle(Color.acorn700)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.acorn600)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.acorn50, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14).stroke(Color.acorn200, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.appFont(.bold, size: 13))
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var coachTitle: String {
        "다람이 코치: \(recommendedComparisonSummary.badge)"
    }

    private var coachMessage: String {
        recommendedComparisonSummary.coachMessage
    }

    private var headerDateLabel: String {
        return KoDate.dateWithClock(model.endedAt)
    }

    private func formatDurationShort(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let mins = total / 60
        let secs = total % 60
        if mins == 0 { return "\(secs)초" }
        if secs == 0 { return "\(mins)분" }
        return "\(mins)분 \(secs)초"
    }

    private var durationDeltaMinutes: Int {
        Int(((model.totalDurationSec - RecommendedBaseline.durationSec) / 60).rounded())
    }

    private var chewingFocusDeltaPercent: Int {
        Int(((model.chewingFraction - RecommendedBaseline.chewingFraction) * 100).rounded())
    }

    private var recommendedComparisonSummary: RecommendedComparisonSummary {
        let chewDelta = model.chewCount - RecommendedBaseline.chewCount
        let speedDelta = model.chewsPerMinute - RecommendedBaseline.chewsPerMinute
        let minuteDelta = durationDeltaMinutes
        let focusDelta = chewingFocusDeltaPercent
        let positiveSignals = [
            chewDelta >= 30,
            minuteDelta >= 1,
            focusDelta >= 5,
            speedDelta <= 3
        ].filter { $0 }.count

        if positiveSignals >= 3 {
            return RecommendedComparisonSummary(
                badge: "권장보다 여유",
                title: "권장 기준보다 천천히, 더 오래 씹은 식사예요",
                detail: "저작 횟수와 씹기 비율이 권장 기준보다 높아요. 이번 리듬은 다음 식사에서도 재현해볼 만해요.",
                coachMessage: "지금처럼 첫 몇 입의 속도를 낮추면 식사 전체 리듬이 안정적으로 이어질 수 있어요.",
                color: .sage600,
                imageName: Mood.happy.imageName
            )
        }

        if chewDelta < -80 || minuteDelta < -3 || speedDelta > 8 {
            return RecommendedComparisonSummary(
                badge: "권장보다 빠름",
                title: "권장 기준보다 짧고 빠른 식사였어요",
                detail: "식사 시간이 권장 기준보다 짧거나 분당 저작 흐름이 빠른 편이에요. 신호 상태와 메뉴 차이도 함께 참고해요.",
                coachMessage: "다음 식사에서는 첫 5분만 의식적으로 천천히 시작해봐요. 처음 속도가 전체 흐름을 잡아줘요.",
                color: .blush500,
                imageName: Mood.sleepy.imageName
            )
        }

        if chewDelta >= 30 || focusDelta >= 5 {
            return RecommendedComparisonSummary(
                badge: "저작 우세",
                title: "권장 기준보다 씹는 흐름이 많은 식사예요",
                detail: "총 저작 횟수나 씹기 비율이 권장 기준보다 높아요. 식사 시간이 크게 짧지 않았다면 좋은 흐름으로 볼 수 있어요.",
                coachMessage: "저작 흐름은 좋아요. 다음에는 중간중간 짧은 쉼을 섞어 더 편안한 리듬을 만들어봐요.",
                color: .acorn700,
                imageName: Mood.champ.imageName
            )
        }

        return RecommendedComparisonSummary(
            badge: "권장 근처",
            title: "권장 기준과 비슷한 리듬의 식사예요",
            detail: "저작 횟수와 식사 시간이 권장 기준 범위 안에 있어요. 꾸준히 쌓이면 나만의 리듬 변화도 볼 수 있어요.",
            coachMessage: "큰 흔들림 없이 식사했어요. 다음 목표는 한 끼에서 씹기 비율을 조금 더 높여보는 거예요.",
            color: .butter600,
            imageName: Mood.puffy.imageName
        )
    }

    private func signedDelta(_ value: Int, suffix: String) -> String {
        if value == 0 { return "±0\(suffix)" }
        return value > 0 ? "+\(value)\(suffix)" : "\(value)\(suffix)"
    }
}

/// 권장 기준(목표)값. 모집단 평균이 아니라 "한 끼에 이 정도면 충분히 천천히 씹은 것"이라는
/// 권장 목표다. 개인 평균 집계 인프라가 없으므로 정직하게 '권장 기준'으로 노출한다.
private enum RecommendedBaseline {
    static let chewCount = 300
    static let durationSec: Double = 720      // 12분
    static let chewsPerMinute: Double = 28
    static let chewingFraction: Double = 0.6
}

private struct RecommendedComparisonSummary {
    let badge: String
    let title: String
    let detail: String
    let coachMessage: String
    let color: Color
    let imageName: String
}

private struct RecommendedDeltaBar: View {
    let ratio: Double
    let color: Color

    private var clampedRatio: CGFloat {
        CGFloat(max(-1, min(1, ratio)))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let center = width / 2
            let markerX = center + clampedRatio * width * 0.42
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.hairline.opacity(0.8))
                Rectangle()
                    .fill(Color.textTertiary.opacity(0.32))
                    .frame(width: 1)
                    .offset(x: center)
                Capsule()
                    .fill(color.opacity(0.24))
                    .frame(width: abs(markerX - center), height: 8)
                    .offset(x: min(center, markerX))
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(color, lineWidth: 2))
                    .offset(x: min(max(0, markerX - 6), width - 12))
            }
        }
    }
}

/// 씹기 점수 산정 방식 가이드. "씹기 점수" 옆 ⓘ 버튼이 시트로 띄운다.
/// 내용은 `SessionScore.compute(_:)`의 4요소(속도·리듬·연속·길이)와 등급 기준을 사용자 언어로 설명.
private struct ScoreGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("씹기 점수는 한 끼를 얼마나 천천히·꼼꼼히 씹었는지를 0~100으로 나타낸 값이에요. 아래 네 요소를 각각 0~100으로 매기고 평균낸 점수예요.")
                        .font(.appFont(.semibold, size: 14))
                        .foregroundStyle(Color.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 10) {
                        guideRow("속도", "분당 저작 횟수예요. 권장(약 28회/분)에 가까울수록 높고, 너무 빠르거나 느리면 낮아져요.", .blush500)
                        guideRow("비율", "식사 중 실제로 씹은 시간의 비율(씹기 비율)이에요. 50% 이상이면 만점에 가까워요.", .butter600)
                        guideRow("횟수", "한 끼의 총 저작 횟수예요. 약 200회 이상이면 만점에 가까워요.", .acorn700)
                        guideRow("시간", "식사에 들인 시간이에요. 약 12분 근처에서 가장 높아요.", .sage600)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("등급 기준")
                            .font(.appFont(.heavy, size: 14))
                            .foregroundStyle(Color.textPrimary)
                        Text("80점 이상은 잘 씹은 식사, 60~79점은 보통, 60점 미만은 조금 빠른 편이에요.")
                            .font(.appFont(.semibold, size: 13))
                            .foregroundStyle(Color.textSecondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("AirPods 모션 센서 신호를 기기 안에서 분석해 추정한 값이라, 정확한 측정값이 아닌 참고용 지표예요.")
                        .font(.appFont(.medium, size: 12))
                        .foregroundStyle(Color.textTertiary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.pageBackground.ignoresSafeArea())
            .navigationTitle("씹기 점수 가이드")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .font(.appFont(.bold, size: 15))
                        .foregroundStyle(Color.acorn700)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func guideRow(_ title: String, _ desc: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.appFont(.heavy, size: 14))
                .foregroundStyle(color)
                .frame(width: 36, alignment: .leading)
            Text(desc)
                .font(.appFont(.semibold, size: 13))
                .foregroundStyle(Color.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// 얕은 점선 구분선. 카드를 중첩하지 않고 섹션 안에서 영역만 가볍게 가른다.
struct DashedDivider: View {
    var color: Color = Color.textTertiary.opacity(0.25)

    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(color)
        }
        .frame(height: 1)
    }
}

#Preview("Good 분석") {
    ZStack {
        Color.pageBackground.ignoresSafeArea()
        ReportCardView(model: ReportCardModel(
            score: 82,
            grade: .good,
            chewCount: 318,
            totalDurationSec: 642,
            chewsPerMinute: 29.7,
            chewingFraction: 0.71,
            chewingSeconds: 456,
            restSeconds: 186,
            speedScore: 89,
            rhythmScore: 100,
            continuityScore: 100,
            lengthScore: 87,
            caption: "오늘은 천천히 잘 씹었어요. 한 입에 30회 목표 달성!",
            mood: .champ,
            endedAt: Date()
        ), onDeepReport: {})
        .padding(20)
    }
}

#Preview("Soso 분석") {
    ZStack {
        Color.pageBackground.ignoresSafeArea()
        ReportCardView(model: ReportCardModel(
            score: 65,
            grade: .soso,
            chewCount: 192,
            totalDurationSec: 420,
            chewsPerMinute: 27.4,
            chewingFraction: 0.52,
            chewingSeconds: 218,
            restSeconds: 202,
            speedScore: 96,
            rhythmScore: 100,
            continuityScore: 96,
            lengthScore: 50,
            caption: nil,
            mood: .puffy,
            endedAt: Date()
        ))
        .padding(20)
    }
}

#Preview("Bad 분석") {
    ZStack {
        Color.pageBackground.ignoresSafeArea()
        ReportCardView(model: ReportCardModel(
            score: 42,
            grade: .bad,
            chewCount: 87,
            totalDurationSec: 180,
            chewsPerMinute: 29.0,
            chewingFraction: 0.38,
            chewingSeconds: 68,
            restSeconds: 112,
            speedScore: 93,
            rhythmScore: 76,
            continuityScore: 44,
            lengthScore: 10,
            caption: "조금 빨리 먹은 것 같아요. 다음 식사엔 한 입 30회를 의식해 봐요.",
            mood: .sleepy,
            endedAt: Date()
        ), onDeepReport: {})
        .padding(20)
    }
}

// MARK: - ChewingSessionDTO → ReportCardModel mapper
//
// UI 레이어가 DTO 변경에 직접 결합되지 않도록 카드용 변환 진입점만 이 extension에서
// 노출. 점수 산출은 `SessionScore.compute(_:)`에 위임.

extension ReportCardModel {
    /// `ChewingSessionDTO` → 카드 모델. `durationSec < 60`이거나 분석 5필드가
    /// 채워지지 않은 세션에서 nil 반환 → 호출자가 빈 상태 카드를 표시 (PRD #3 빈 분석 카드 "분석을 만들지 못했어요").
    static func from(_ dto: ChewingSessionDTO) -> ReportCardModel? {
        guard dto.durationSec >= 60 else { return nil }
        guard let score = SessionScore.compute(dto) else { return nil }
        let mins = max(0.001, dto.durationSec / 60)
        let chews = dto.estimatedTotalChews ?? 0
        let chewsPerMin = Double(chews) / mins
        let grade = Grade(scoreGrade: score.grade)
        let mood = Mood(grade: grade, score: score.total)
        let caption = CaptionPool.report(for: grade)
        return ReportCardModel(
            score: score.total,
            grade: grade,
            chewCount: chews,
            totalDurationSec: dto.durationSec,
            chewsPerMinute: chewsPerMin,
            chewingFraction: dto.chewingFraction ?? 0,
            chewingSeconds: dto.chewingSeconds ?? 0,
            restSeconds: dto.restSeconds ?? 0,
            speedScore: score.speed,
            rhythmScore: score.rhythm,
            continuityScore: score.continuity,
            lengthScore: score.length,
            caption: caption,
            mood: mood,
            endedAt: dto.endedAt
        )
    }
}

private extension ReportCardModel.Grade {
    init(scoreGrade: SessionScore.Grade) {
        switch scoreGrade {
        case .good: self = .good
        case .soso: self = .soso
        case .bad:  self = .bad
        }
    }
}

private extension Mood {
    /// 점수 등급+총점 → 다람이 일러스트 매핑. 결정적(같은 세션은 항상 같은 표정).
    /// 이전엔 good에서 `Bool.random()`이라 리드로우마다 표정이 바뀌었다.
    init(grade: ReportCardModel.Grade, score: Int) {
        switch grade {
        case .good: self = score >= 90 ? .champ : .happy
        case .soso: self = .puffy
        case .bad:  self = .sleepy
        }
    }
}

/// 카드 frame을 유지한 채 본문에 안내 메시지를 표시하는 빈 카드. 기본값은 분석 5필드가
/// 없는 세션(시뮬레이터/AirPods 미연결/60초 미만)용. emoji/title/subtitle을 갈아끼우면
/// "오늘 식사 0건" 같은 다른 빈 상태에도 같은 디자인으로 재사용 가능.
struct EmptyReportCardView: View {
    var emoji: String = "🐿️"
    var title: String = "분석을 만들지 못했어요"
    var subtitle: String = "식사 시간이 너무 짧거나 AirPods 신호를 받지 못했어요."

    var body: some View {
        VStack(spacing: 14) {
            Text(emoji).font(.appFont(.regular, size: 40))
            Text(title)
                .font(.appFont(.heavy, size: 18))
                .foregroundStyle(Color.textPrimary)
            Text(subtitle)
                .font(.appFont(.semibold, size: 15))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 24))
    }
}
