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
    let chewRestSegments: [ChewRestSegment]
    /// 리포트 생성 시점의 서버 권장 기준 스냅샷.
    let rateRecommendation: RateRecommendation
    let recommendedChewingFraction: Double
    let recommendedChewCount: Int
    let recommendedDurationSec: Double
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

    init(
        score: Int,
        grade: Grade,
        chewCount: Int,
        totalDurationSec: Double,
        chewsPerMinute: Double,
        chewingFraction: Double,
        chewingSeconds: Double,
        restSeconds: Double,
        chewRestSegments: [ChewRestSegment] = [],
        speedScore: Int,
        rhythmScore: Int,
        continuityScore: Int,
        lengthScore: Int,
        caption: String?,
        mood: Mood,
        rateRecommendation: RateRecommendation,
        recommendedChewingFraction: Double,
        recommendedChewCount: Int,
        recommendedDurationSec: Double,
        endedAt: Date
    ) {
        self.score = score
        self.grade = grade
        self.chewCount = chewCount
        self.totalDurationSec = totalDurationSec
        self.chewsPerMinute = chewsPerMinute
        self.chewingFraction = chewingFraction
        self.chewingSeconds = chewingSeconds
        self.restSeconds = restSeconds
        self.chewRestSegments = chewRestSegments
        self.speedScore = speedScore
        self.rhythmScore = rhythmScore
        self.continuityScore = continuityScore
        self.lengthScore = lengthScore
        self.caption = caption
        self.mood = mood
        self.rateRecommendation = rateRecommendation
        self.recommendedChewingFraction = recommendedChewingFraction
        self.recommendedChewCount = recommendedChewCount
        self.recommendedDurationSec = recommendedDurationSec
        self.endedAt = endedAt
    }

    /// 기존 scalar fixture/call site를 단일 목표 정책으로 보존한다.
    init(
        score: Int,
        grade: Grade,
        chewCount: Int,
        totalDurationSec: Double,
        chewsPerMinute: Double,
        chewingFraction: Double,
        chewingSeconds: Double,
        restSeconds: Double,
        chewRestSegments: [ChewRestSegment] = [],
        speedScore: Int,
        rhythmScore: Int,
        continuityScore: Int,
        lengthScore: Int,
        caption: String?,
        mood: Mood,
        recommendedChewsPerMinute: Double,
        recommendedChewingFraction: Double,
        recommendedChewCount: Int,
        recommendedDurationSec: Double,
        endedAt: Date
    ) {
        self.init(
            score: score,
            grade: grade,
            chewCount: chewCount,
            totalDurationSec: totalDurationSec,
            chewsPerMinute: chewsPerMinute,
            chewingFraction: chewingFraction,
            chewingSeconds: chewingSeconds,
            restSeconds: restSeconds,
            chewRestSegments: chewRestSegments,
            speedScore: speedScore,
            rhythmScore: rhythmScore,
            continuityScore: continuityScore,
            lengthScore: lengthScore,
            caption: caption,
            mood: mood,
            rateRecommendation: .init(target: recommendedChewsPerMinute),
            recommendedChewingFraction: recommendedChewingFraction,
            recommendedChewCount: recommendedChewCount,
            recommendedDurationSec: recommendedDurationSec,
            endedAt: endedAt
        )
    }

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

    struct RateRecommendation: Equatable {
        let min: Double
        let max: Double
        let target: Double?

        init(target: Double) {
            self.min = target
            self.max = target
            self.target = target
        }

        init(min: Double, max: Double) {
            self.min = min
            self.max = max
            self.target = nil
        }

        var displayText: String {
            if let target {
                return formatRecommendedChewsPerMinute(target)
            }
            return "\(Int(min.rounded()))~\(Int(max.rounded()))"
        }

        func delta(from value: Double) -> Double {
            if value < min { return value - min }
            if value > max { return value - max }
            return 0
        }

        func normalizedDelta(from value: Double) -> Double {
            let boundary = value < min ? min : max
            return delta(from: value) / Swift.max(boundary * 0.5, 1)
        }
    }

    struct ChewRestSegment: Equatable {
        let isChewing: Bool
        let durationSec: Double

        static func fromTimeline(_ timeline: String?) -> [ChewRestSegment] {
            guard let timeline else { return [] }

            var segments: [ChewRestSegment] = []
            var currentIsChewing: Bool?
            var currentDuration = 0

            for byte in timeline.utf8 {
                guard byte == CharacterCode.zero || byte == CharacterCode.one else { continue }

                let isChewing = byte == CharacterCode.one
                if currentIsChewing == isChewing {
                    currentDuration += 1
                } else {
                    if let currentIsChewing, currentDuration > 0 {
                        segments.append(ChewRestSegment(
                            isChewing: currentIsChewing,
                            durationSec: Double(currentDuration)
                        ))
                    }
                    currentIsChewing = isChewing
                    currentDuration = 1
                }
            }

            if let currentIsChewing, currentDuration > 0 {
                segments.append(ChewRestSegment(
                    isChewing: currentIsChewing,
                    durationSec: Double(currentDuration)
                ))
            }

            return segments
        }

        /// 시간순 구간 배열을 `columnCount`개의 균등 시간 칸으로 다운샘플한다.
        /// 각 칸이 덮는 시간 구간에서 씹기 초가 절반 이상이면 씹기 칸으로 보고
        /// (다수결), 같은 상태의 인접 칸은 하나의 런으로 합친다. 반환값은
        /// (씹기여부, 칸 수)의 시간순 순서열 — 뷰가 칸 수 × 칸 너비로 그린다.
        /// 칸당 시간이 1초를 크게 넘으면(긴 세션) 칸 안의 소수 펄스는 다수결에서
        /// 탈락할 수 있다. total ≤ 0·빈 입력·columnCount ≤ 0이면 빈 배열.
        static func dominantRuns(
            _ segments: [ChewRestSegment],
            total: Double,
            columnCount: Int
        ) -> [(isChewing: Bool, columns: Int)] {
            guard columnCount > 0, total > 0, !segments.isEmpty else { return [] }
            let secondsPerColumn = total / Double(columnCount)

            // 구간별 누적 시간 경계 [start, end).
            var bounds: [(start: Double, end: Double, isChewing: Bool)] = []
            bounds.reserveCapacity(segments.count)
            var cursor = 0.0
            for segment in segments {
                bounds.append((start: cursor, end: cursor + segment.durationSec, isChewing: segment.isChewing))
                cursor += segment.durationSec
            }

            var runs: [(isChewing: Bool, columns: Int)] = []
            // 칸도 구간도 시간순이라, 이 칸 시작 이전에 끝난 구간은 다시 안 본다.
            var head = 0
            for column in 0..<columnCount {
                let sliceStart = Double(column) * secondsPerColumn
                let sliceEnd = sliceStart + secondsPerColumn
                while head < bounds.count && bounds[head].end <= sliceStart { head += 1 }

                var chewingSeconds = 0.0
                var index = head
                while index < bounds.count && bounds[index].start < sliceEnd {
                    let overlap = min(bounds[index].end, sliceEnd) - max(bounds[index].start, sliceStart)
                    if overlap > 0 && bounds[index].isChewing { chewingSeconds += overlap }
                    index += 1
                }

                let isChewing = chewingSeconds >= secondsPerColumn / 2
                if let last = runs.last, last.isChewing == isChewing {
                    runs[runs.count - 1].columns += 1
                } else {
                    runs.append((isChewing: isChewing, columns: 1))
                }
            }
            return runs
        }

        private enum CharacterCode {
            static let zero = UInt8(ascii: "0")
            static let one = UInt8(ascii: "1")
        }
    }
}

/// 점수 카운트업 값. progress 0→1 동안 0→target 선형, 0~1 밖은 클램프.
/// 씹기 점수 섹션의 카운트업 애니메이션에 쓰이고 `ReportCardModelTests`가 가드한다.
func scoreCountUpValue(progress: Double, target: Int) -> Int {
    let clamped = min(max(progress, 0), 1)
    return Int((clamped * Double(target)).rounded())
}

/// 서버 기준값의 소수 정밀도를 보존하되 정수에는 불필요한 `.0`을 붙이지 않는다.
func formatRecommendedChewsPerMinute(_ value: Double) -> String {
    guard value.isFinite else { return String(value) }
    if value.rounded(.towardZero) == value {
        return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    return String(value)
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
        AppCard(padding: AppSpacing.cardContentLarge) {
            VStack(spacing: AppSpacing.verticalLoose) {
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
        }
        .sheet(isPresented: $showScoreGuide) {
            ScoreGuideView(model: model)
        }
    }

    /// 섹션 사이 실선 구분선(배경 카드 대신). 점선은 섹션 안 영역 구분에만 따로 쓴다.
    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.borderDefault)
            .frame(height: AppSize.border)
            .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AppSpacing.one) {
                Text(headerDateLabel)
                    .font(.appFont(.semiboldCallout))
                    .foregroundStyle(Color.textMuted)
                Text("식사 리포트")
                    .font(.appFont(.display))
                    .foregroundStyle(Color.textDefault)
            }
            Spacer()
        }
    }

    // MARK: - 씹기 점수 (서버 스냅샷 노출)

    /// 내부에서 계산만 하고 버리던 0~100 점수 + 4축(속도·리듬·연속·길이)을 실제로 노출한다.
    /// 흐리멍덩한 형용사 배지의 정량 근거가 된다.
    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.three) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.oneHalf) {
                Text("씹기 점수")
                    .font(.appFont(.heavyBody))
                    .foregroundStyle(Color.textDefault)
                if !rendersStatically {
                    Button { showScoreGuide = true } label: {
                        Image(systemName: "info.circle")
                            .font(.appFont(.semibold, size: Metrics.infoIcon))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("씹기 점수 설명 보기")
                }
                Spacer(minLength: 0)
                Text("\(scoreCountUpValue(progress: rendersStatically ? 1 : scoreProgress, target: model.score))")
                    .font(.appFont(.heavyDisplay))
                    .foregroundStyle(scoreColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("/ 100")
                    .font(.appFont(.boldCaption))
                    .foregroundStyle(Color.textTertiary)
            }
            // 라벨은 실제 측정값과 1:1로 맞춘다(점수 4축 = 권장 4지표와 동일 대상):
            // speed=분당 속도, rhythm=씹은 시간 비율, continuity=총 저작 횟수, length=식사 시간.
            VStack(spacing: AppSpacing.two) {
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
        HStack(spacing: AppSpacing.inner) {
            Text(label)
                .font(.appFont(.boldCaption))
                .foregroundStyle(Color.textMuted)
                .frame(width: Metrics.scoreAxisLabelWidth, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.borderDefault)
                    Capsule().fill(scoreColor.opacity(0.85))
                        .frame(width: max(Metrics.scoreAxisMinFillWidth, geo.size.width * CGFloat(max(0, min(100, value))) / 100))
                }
            }
            .frame(height: AppSpacing.two)
            Text("\(value)")
                .font(.appFont(.heavyCaption))
                .foregroundStyle(Color.textDefault)
                .monospacedDigit()
                .frame(width: Metrics.scoreAxisValueWidth, alignment: .trailing)
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
        return VStack(alignment: .leading, spacing: AppSpacing.four) {
            // 헤더 — "권장 기준보다 ~~한 식사였어요" 한 줄만(배지 제거). 색은 카드 배경으로만 준다(플랫).
            Text(summary.title)
                .font(.appFont(.heavyTitleCompact))
                .foregroundStyle(Color.textDefault)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: AppSpacing.four), GridItem(.flexible(), spacing: AppSpacing.four)],
                spacing: AppSpacing.inputH
            ) {
                recommendedComparisonCell(
                    label: "저작 횟수",
                    current: "약 \(model.chewCount.koLocale)회",
                    recommended: "권장 \(model.recommendedChewCount.koLocale)회",
                    delta: signedDelta(model.chewCount - model.recommendedChewCount, suffix: "회"),
                    // 풀스케일 = 권장 기준의 ±50%. 네 지표가 동일한 상대 논리로 막대를 채운다.
                    ratio: Double(model.chewCount - model.recommendedChewCount) / (Double(model.recommendedChewCount) * 0.5),
                    color: .acorn700
                )
                recommendedComparisonCell(
                    label: "식사 시간",
                    current: formatDurationShort(model.totalDurationSec),
                    recommended: "권장 \(formatDurationShort(model.recommendedDurationSec))",
                    delta: signedDelta(durationDeltaMinutes, suffix: "분"),
                    ratio: Double(durationDeltaMinutes) / (model.recommendedDurationSec / 60 * 0.5),
                    color: .sage600
                )
                recommendedComparisonCell(
                    label: "식사 속도",
                    current: "약 \(Int(model.chewsPerMinute.rounded()))회/분",
                    recommended: "권장 \(model.rateRecommendation.displayText)회/분",
                    delta: signedDelta(Int(model.rateRecommendation.delta(from: model.chewsPerMinute).rounded()), suffix: "회/분"),
                    ratio: model.rateRecommendation.normalizedDelta(from: model.chewsPerMinute),
                    color: .blush500
                )
                recommendedComparisonCell(
                    label: "씹기 비율",
                    current: "\(Int((model.chewingFraction * 100).rounded()))%",
                    recommended: "권장 \(Int(model.recommendedChewingFraction * 100))%",
                    delta: signedDelta(chewingFocusDeltaPercent, suffix: "%"),
                    ratio: Double(chewingFocusDeltaPercent) / (model.recommendedChewingFraction * 100 * 0.5),
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
        VStack(alignment: .leading, spacing: AppSpacing.badgeH) {
            HStack(spacing: AppSpacing.oneHalf) {
                Text(label)
                    .font(.appFont(.semiboldCallout))
                    .foregroundStyle(Color.textMuted)
                Spacer(minLength: 0)
                Text(delta)
                    .font(.appFont(.heavyMicro))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .padding(.horizontal, AppSpacing.badgeH)
                    .padding(.vertical, AppSpacing.badgeV)
                    .background(color.opacity(0.12), in: Capsule())
            }
            Text(current)
                .font(.appFont(.heavyTitle))
                .foregroundStyle(Color.textDefault)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .monospacedDigit()
            RecommendedDeltaBar(ratio: ratio, color: color)
                .frame(height: AppSpacing.three)
            Text(recommended)
                .font(.appFont(.semiboldCallout))
                .foregroundStyle(Color.textMuted.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppSpacing.one)
    }

    private var coachPanel: some View {
        let summary = recommendedComparisonSummary
        return HStack(spacing: AppSpacing.three) {
            Image(summary.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: Metrics.coachAvatar, height: Metrics.coachAvatar)
                .background(Color.butter100.opacity(0.7), in: Circle())
            VStack(alignment: .leading, spacing: AppSpacing.microLabelGap) {
                Text(coachTitle)
                    .font(.appFont(.heavyBody))
                    .foregroundStyle(Color.textDefault)
                Text(coachMessage)
                    .font(.appFont(.semiboldCallout))
                    .foregroundStyle(Color.textMuted)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.cell)
        .frame(maxWidth: .infinity)
        .background(Color.statusSuccessMuted.opacity(0.82), in: RoundedRectangle(cornerRadius: AppRadius.container))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.container)
                .stroke(Color.statusSuccessBorder, lineWidth: AppSize.border)
        )
    }

    // MARK: - 씹기 · 쉬기 구간 바

    private var chewRestSection: some View {
        let segments = model.visibleChewRestSegments
        let total = segments.reduce(0) { $0 + $1.durationSec }
        return VStack(alignment: .leading, spacing: AppSpacing.two) {
            sectionTitle("씹기 · 쉬기 구간")
            Canvas { context, size in
                // 고정 너비 바를 1pt 칸으로 쪼개고, 각 칸을 그 시간 구간의 다수
                // 상태(씹기/쉬기 초가 더 많은 쪽)로 칠한다(다수결 다운샘플). 폭
                // 비율은 실제 씹기 비율과 맞고, 구간 폭이 1pt에 못 미쳐 서브픽셀로
                // 사라지던 문제가 칸 해상도로 해소된다. 단 칸당 시간이 1초를 크게
                // 넘는 긴 세션에선 칸 안의 소수 펄스는 다수결에서 묻힐 수 있다.
                let columnCount = max(1, Int(size.width.rounded()))
                let columnWidth = size.width / CGFloat(columnCount)
                let runs = ReportCardModel.ChewRestSegment.dominantRuns(
                    segments, total: total, columnCount: columnCount
                )
                var x: CGFloat = 0
                for run in runs {
                    let width = CGFloat(run.columns) * columnWidth
                    let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                    context.fill(
                        Path(rect),
                        with: .color(run.isChewing ? Color.sage500 : Color.acorn200)
                    )
                    x += width
                }
            }
            .frame(height: AppSpacing.cell)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.badgeH))
            HStack(spacing: AppSpacing.four) {
                legendDot(color: .sage500, label: "씹기 \(formatDurationShort(model.chewingSeconds))")
                legendDot(color: .acorn200, label: "쉬기 \(formatDurationShort(model.restSeconds))")
                Spacer(minLength: 0)
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: AppSpacing.microLabelGap) {
            Circle().fill(color).frame(width: AppSpacing.two, height: AppSpacing.two)
            Text(label)
                .font(.appFont(.semiboldCallout))
                .foregroundStyle(Color.textMuted)
        }
    }

    private var captionSection: some View {
        HStack(alignment: .top, spacing: AppSpacing.inner) {
            Image(systemName: "quote.opening")
                .font(.appFont(.boldCallout))
                .foregroundStyle(Color.acorn300)
            Text(model.caption ?? "오늘 한 끼 잘 먹었어요.")
                .font(.appFont(.semiboldBody))
                .foregroundStyle(Color.textMuted)
                .lineSpacing(3)
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.cell)
        .frame(maxWidth: .infinity)
        .background(Color.bgSunken.opacity(0.5), in: RoundedRectangle(cornerRadius: AppRadius.element))
    }

    private var deepReportCTA: some View {
        Button(action: { onDeepReport?() }) {
            HStack(spacing: AppSpacing.two) {
                Text("심층 분석 보기")
                    .font(.appFont(.boldLabel))
                    .foregroundStyle(Color.acorn700)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.appFont(.boldCaption))
                    .foregroundStyle(Color.acorn600)
            }
            .padding(.horizontal, AppSpacing.four)
            .padding(.vertical, AppSpacing.cell)
            .frame(maxWidth: .infinity)
            .background(Color.bgSunken, in: RoundedRectangle(cornerRadius: AppRadius.element))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.element).stroke(Color.borderEmphasized, lineWidth: AppSize.border)
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.appFont(.boldCallout))
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
        Int(((model.totalDurationSec - model.recommendedDurationSec) / 60).rounded())
    }

    private var chewingFocusDeltaPercent: Int {
        Int(((model.chewingFraction - model.recommendedChewingFraction) * 100).rounded())
    }

    private var recommendedComparisonSummary: RecommendedComparisonSummary {
        let chewDelta = model.chewCount - model.recommendedChewCount
        let speedDelta = model.rateRecommendation.delta(from: model.chewsPerMinute)
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
                    .frame(width: Metrics.chartHairline)
                    .offset(x: center)
                Capsule()
                    .fill(color.opacity(0.24))
                    .frame(width: abs(markerX - center), height: Metrics.chartDeltaHeight)
                    .offset(x: min(center, markerX))
                Circle()
                    .fill(Color.bgSurface)
                    .frame(width: Metrics.chartMarkerWidth, height: Metrics.chartMarkerWidth)
                    .overlay(Circle().stroke(color, lineWidth: 2))
                    .offset(x: min(max(0, markerX - Metrics.chartMarkerRadius), width - Metrics.chartMarkerWidth))
            }
        }
    }
}

/// 씹기 점수 산정 방식 가이드. "씹기 점수" 옆 ⓘ 버튼이 시트로 띄운다.
/// 서버 리포트 스냅샷의 4요소와 권장 기준을 사용자 언어로 설명한다.
private struct ScoreGuideView: View {
    @Environment(\.dismiss) private var dismiss
    let model: ReportCardModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.four) {
                    Text("씹기 점수는 한 끼를 얼마나 천천히·꼼꼼히 씹었는지를 0~100으로 나타낸 값이에요. 아래 네 요소를 각각 0~100으로 매기고 평균낸 점수예요.")
                        .font(.appFont(.semiboldLabel))
                        .foregroundStyle(Color.textMuted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: AppSpacing.inner) {
                        guideRow("속도", "서버 권장 기준은 분당 약 \(model.rateRecommendation.displayText)회예요.", .blush500)
                        guideRow("비율", "서버 권장 기준은 식사 중 씹기 비율 \(Int((model.recommendedChewingFraction * 100).rounded()))%예요.", .butter600)
                        guideRow("횟수", "서버 권장 기준은 한 끼 \(model.recommendedChewCount.koLocale)회예요.", .acorn700)
                        guideRow("시간", "서버 권장 기준은 한 끼 약 \(Int((model.recommendedDurationSec / 60).rounded()))분이에요.", .sage600)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.two) {
                        Text("등급 기준")
                            .font(.appFont(.heavyLabel))
                            .foregroundStyle(Color.textDefault)
                        Text("등급은 서버가 리포트를 생성한 시점의 점수 정책에 따라 저장된 값을 표시해요.")
                            .font(.appFont(.semiboldCallout))
                            .foregroundStyle(Color.textMuted)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("AirPods 모션 센서 신호를 기기 안에서 분석해 추정한 값이라, 정확한 측정값이 아닌 참고용 지표예요.")
                        .font(.appFont(.mediumCaption))
                        .foregroundStyle(Color.textSubtle)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AppSpacing.page)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.bgPage.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    AppSheetTitleText(title: "씹기 점수 가이드")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AppSheetTextActionButton(title: "닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func guideRow(_ title: String, _ desc: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.three) {
            Text(title)
                .font(.appFont(.heavyLabel))
                .foregroundStyle(color)
                .frame(width: Metrics.guideLabelWidth, alignment: .leading)
            Text(desc)
                .font(.appFont(.semiboldCallout))
                .foregroundStyle(Color.textMuted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.three)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.element))
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
        .frame(height: Metrics.chartHairline)
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
            rateRecommendation: .init(target: 28),
            recommendedChewingFraction: 0.5,
            recommendedChewCount: 200,
            recommendedDurationSec: 720,
            endedAt: Date()
        ), onDeepReport: {})
        .padding(AppSpacing.page)
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
            rateRecommendation: .init(target: 28),
            recommendedChewingFraction: 0.5,
            recommendedChewCount: 200,
            recommendedDurationSec: 720,
            endedAt: Date()
        ))
        .padding(AppSpacing.page)
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
            rateRecommendation: .init(target: 28),
            recommendedChewingFraction: 0.5,
            recommendedChewCount: 200,
            recommendedDurationSec: 720,
            endedAt: Date()
        ), onDeepReport: {})
        .padding(AppSpacing.page)
    }
}

// MARK: - ChewingSessionDTO → ReportCardModel mapper
//
// UI 레이어가 DTO 변경에 직접 결합되지 않도록 카드용 변환 진입점만 이 extension에서
// 노출. 점수와 권장 기준은 서버가 저장한 `mealReport` 스냅샷만 사용한다.

extension ReportCardModel {
    /// `ChewingSessionDTO` → 카드 모델. GENERATED 서버 리포트가 완전할 때만 모델을 만든다.
    static func from(_ dto: ChewingSessionDTO) -> ReportCardModel? {
        guard let report = MealSessionReportability.completeGeneratedReport(dto.mealReport, sessionId: dto.id),
              let totalScore = report.totalScore,
              let axes = report.axisScores,
              let metrics = report.metrics,
              let reportGrade = report.grade,
              let grade = Grade(reportGrade: reportGrade),
              let baseline = report.recommendedBaseline else { return nil }
        let rate: Double
        let recommendation: RateRecommendation
        switch report.scorePolicyVersion {
        case "legacy-ios-v1":
            guard let legacyRate = metrics.legacyMealRatePerMin,
                  let target = baseline.chewingRatePerMin.target else { return nil }
            rate = legacyRate
            recommendation = .init(target: target)
        case "meal-score-v1":
            guard let v1Rate = metrics.chewingRatePerMin,
                  let min = baseline.chewingRatePerMin.min,
                  let max = baseline.chewingRatePerMin.max else { return nil }
            rate = v1Rate
            recommendation = .init(min: min, max: max)
        default:
            return nil
        }
        let mood = Mood(grade: grade, score: totalScore)
        let caption = CaptionPool.report(for: grade)
        let chewingRatio = min(max(metrics.chewingTimeRatio, 0), 1)
        let chewingSeconds = metrics.mealDurationSec * chewingRatio
        let restSeconds = metrics.mealDurationSec * (1 - chewingRatio)
        return ReportCardModel(
            score: totalScore,
            grade: grade,
            chewCount: metrics.totalChewCount,
            totalDurationSec: metrics.mealDurationSec,
            chewsPerMinute: rate,
            chewingFraction: metrics.chewingTimeRatio,
            chewingSeconds: chewingSeconds,
            restSeconds: restSeconds,
            chewRestSegments: [],
            speedScore: axes.chewingRate,
            rhythmScore: axes.chewingTimeRatio,
            continuityScore: axes.totalChewCount,
            lengthScore: axes.mealDuration,
            caption: caption,
            mood: mood,
            rateRecommendation: recommendation,
            recommendedChewingFraction: baseline.chewingTimeRatio,
            recommendedChewCount: baseline.totalChewCount,
            recommendedDurationSec: baseline.mealDurationSec,
            endedAt: dto.endedAt
        )
    }
}

private extension ReportCardModel {
    var visibleChewRestSegments: [ChewRestSegment] {
        let timelineSegments = chewRestSegments.filter { $0.durationSec > 0 }
        if !timelineSegments.isEmpty {
            return timelineSegments
        }

        return [
            ChewRestSegment(isChewing: true, durationSec: chewingSeconds),
            ChewRestSegment(isChewing: false, durationSec: restSeconds),
        ].filter { $0.durationSec > 0 }
    }
}

private extension ReportCardModel.Grade {
    init?(reportGrade: MealReportGradeDTO) {
        switch reportGrade {
        case .good: self = .good
        case .soso: self = .soso
        case .bad:  self = .bad
        case .unknown: return nil
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
/// 없는 세션(시뮬레이터/AirPods 미연결/30초 미만)용. emoji/title/subtitle을 갈아끼우면
/// "오늘 식사 0건" 같은 다른 빈 상태에도 같은 디자인으로 재사용 가능.
struct EmptyReportCardView: View {
    var emoji: String = "🐿️"
    var title: String = "분석을 만들지 못했어요"
    var subtitle: String = "식사 시간이 너무 짧거나 AirPods 신호를 받지 못했어요."

    var body: some View {
        AppEmptyState(
            spacing: AppSpacing.cell,
            title: title,
            message: subtitle,
            titleFont: .heavyHeadlineLarge,
            messageFont: .semiboldBody
        ) {
            Text(emoji)
                .font(.appFont(.regularEmojiXXLarge))
        }
        .padding(.vertical, Metrics.emptyStateVerticalPadding)
        .padding(.horizontal, AppSpacing.six)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: AppRadius.lg))
    }
}

private enum Metrics {
    static let scoreAxisLabelWidth: CGFloat = 28
    static let scoreAxisValueWidth: CGFloat = 26
    static let scoreAxisMinFillWidth: CGFloat = 6
    static let coachAvatar = AppSize.visualMedium
    static let chartHairline = AppSize.border
    static let chartMarkerWidth = AppSize.iconXSmall
    static let chartMarkerRadius = AppSize.indicatorSmall
    static let chartDeltaHeight = AppSpacing.two
    static let guideLabelWidth: CGFloat = 36
    static let emptyStateVerticalPadding: CGFloat = 48
    static let infoIcon = AppSize.iconCompact
}
