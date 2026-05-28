import SwiftUI

/// 식사 후 분석 리포트 카드의 표시 모델. `ChewingSessionDTO` → 이 모델로 변환하는
/// 매퍼는 아래 extension에서 노출. UI 컴포넌트가 DTO 변경에 직접 결합되지 않도록 분리.
struct ReportCardModel: Equatable {
    /// 식사 점수 0~100.
    let score: Int
    /// 점수 등급. 컬러/라벨/이모지 분기.
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
    /// 점수 4요소 분해 (각 0~100) — "왜 이 점수인지" 근거를 그리드에 노출.
    let speedScore: Int
    let rhythmScore: Int
    let continuityScore: Int
    let lengthScore: Int
    /// 한 줄 캡션. nil이면 기본 멘트 fallback.
    let caption: String?
    /// 다람이 일러스트(점수 등급에서 매핑). v1.0 헤더는 이모지를 쓰고, 프리미엄 심층
    /// 리포트(REQ-17)에서 이 캐릭터 표정으로 교체한다.
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

        /// v1.0 헤더 표정 이모지. 프리미엄에서는 다람이 캐릭터로 교체.
        var emoji: String {
            switch self {
            case .good: "😀"
            case .soso: "😐"
            case .bad:  "😪"
            }
        }
    }
}

/// 점수 카운트업 계산. progress 0→0, 1→target. 범위 [0, target] 로 clamp.
/// View와 분리된 순수 함수 — 단위테스트 가능.
func scoreCountUpValue(progress: Double, target: Int) -> Int {
    let clamped = max(0.0, min(1.0, progress))
    return Int((Double(target) * clamped).rounded())
}

/// 식사 후 분석 리포트 카드. 식사 종료 직후 sheet/overlay 표시와 캘린더에서 과거 세션
/// 재현 양쪽에서 동일하게 사용된다. 1080×1920 PNG 공유도 같은 View를 ImageRenderer로 렌더.
///
/// `onDeepReport`가 주어지면 하단에 [심층 분석 보기] CTA(REQ-17 진입)를 노출한다.
/// 기본 nil이라 PNG 공유 렌더처럼 CTA가 불필요한 호출부는 그대로 둔다.
struct ReportCardView: View {
    let model: ReportCardModel
    var onDeepReport: (() -> Void)? = nil

    @State private var scoreProgress: Double = 0
    @State private var showScoreFormula = false

    var body: some View {
        VStack(spacing: 18) {
            header
            scoreSection
            scoreBreakdownGrid
            chewRestSection
            captionSection
            if onDeepReport != nil { deepReportCTA }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.acorn50, .cream, Color.sage50],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .neuoShadow(.md)
        .popover(isPresented: $showScoreFormula, arrowEdge: .bottom) {
            ScoreFormulaPopover(model: model)
                .presentationCompactAdaptation(.popover)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) {
                scoreProgress = 1.0
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerDateLabel)
                    .font(.appFont(.medium, size: 11))
                    .foregroundStyle(Color.ink400)
                Text("식사 리포트")
                    .font(.appFont(.heavy, size: 22))
                    .foregroundStyle(Color.ink800)
            }
            Spacer()
            // v1.0: 점수 구간별 표정 이모지. 프리미엄(REQ-17)에서 다람이 캐릭터로 교체.
            Text(model.grade.emoji)
                .font(.system(size: 40))
                .frame(width: 52, height: 52)
        }
    }

    private var scoreSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(scoreCountUpValue(progress: scoreProgress, target: model.score))")
                    .font(.appFont(.heavy, size: 72))
                    .foregroundStyle(gradeColor)
                    .monospacedDigit()
                Text("점")
                    .font(.appFont(.bold, size: 22))
                    .foregroundStyle(Color.ink400)
            }
            Text(model.grade.label)
                .font(.appFont(.bold, size: 13))
                .foregroundStyle(gradeColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(gradeColor.opacity(0.18), in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - 점수 근거 그리드 (4요소 = 왜 이 점수인지)

    private var scoreBreakdownGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Spacer()
                Button { showScoreFormula = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink400)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("점수 산식 보기")
            }
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                factorCell(
                    label: "속도",
                    value: String(format: "%.0f", model.chewsPerMinute), unit: "회/분",
                    subScore: model.speedScore, reference: "권장 28회/분"
                )
                factorCell(
                    label: "리듬",
                    value: "\(Int((model.chewingFraction * 100).rounded()))", unit: "%",
                    subScore: model.rhythmScore, reference: "쉼 없이 꾸준할수록 ↑"
                )
                factorCell(
                    label: "연속성",
                    value: model.chewCount.koLocale, unit: "회",
                    subScore: model.continuityScore, reference: "꾸준히 씹을수록 ↑"
                )
                factorCell(
                    label: "식사 시간",
                    value: formatDurationShort(model.totalDurationSec), unit: nil,
                    subScore: model.lengthScore, reference: "권장 12분 안팎"
                )
            }
        }
    }

    /// 점수 한 요소 카드: 실제 값 + 0~100 요소 점수 미니바 + 기준선 문구.
    private func factorCell(label: String, value: String, unit: String?, subScore: Int, reference: String) -> some View {
        let color = factorColor(subScore)
        return VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.appFont(.medium, size: 11))
                .foregroundStyle(Color.ink400)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.appFont(.heavy, size: 20))
                    .foregroundStyle(Color.ink800)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.appFont(.bold, size: 11))
                        .foregroundStyle(Color.acorn600)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ink100)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * CGFloat(max(0, min(100, subScore))) / 100)
                }
            }
            .frame(height: 5)
            Text(reference)
                .font(.appFont(.medium, size: 9))
                .foregroundStyle(Color.ink400)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
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
                .font(.appFont(.medium, size: 11))
                .foregroundStyle(Color.ink600)
        }
    }

    private var captionSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("💬").font(.appFont(.regular, size: 16))
            Text(model.caption ?? "오늘도 잘 챙겨 먹었어요.")
                .font(.appFont(.regular, size: 13))
                .foregroundStyle(Color.ink600)
                .lineSpacing(3)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
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
            .foregroundStyle(Color.ink600)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gradeColor: Color {
        switch model.grade {
        case .good: Color.sage600
        case .soso: Color.butter500
        case .bad:  Color.blush400
        }
    }

    /// 요소 점수(0~100) → 점수 컬러 토큰. 등급 경계(80/60)와 동일.
    private func factorColor(_ subScore: Int) -> Color {
        switch subScore {
        case 80...:     Color.sage600
        case 60..<80:   Color.butter500
        default:        Color.blush400
        }
    }

    private var headerDateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE · HH:mm"
        return formatter.string(from: model.endedAt)
    }

    private func formatDurationShort(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let mins = total / 60
        let secs = total % 60
        if mins == 0 { return "\(secs)초" }
        if secs == 0 { return "\(mins)분" }
        return "\(mins)분 \(secs)초"
    }
}

#Preview("Good 82점") {
    ZStack {
        Color.cream.ignoresSafeArea()
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

#Preview("Soso 65점") {
    ZStack {
        Color.cream.ignoresSafeArea()
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

#Preview("Bad 42점") {
    ZStack {
        Color.cream.ignoresSafeArea()
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
    /// 채워지지 않은 세션에서 nil 반환 → 호출자가 빈 상태 카드를 표시 (PRD #3 "데이터가 부족해요").
    static func from(_ dto: ChewingSessionDTO) -> ReportCardModel? {
        guard dto.durationSec >= 60 else { return nil }
        guard let score = SessionScore.compute(dto) else { return nil }
        let mins = max(0.001, dto.durationSec / 60)
        let chews = dto.estimatedTotalChews ?? 0
        let chewsPerMin = Double(chews) / mins
        let grade = Grade(scoreGrade: score.grade)
        let mood = Mood(grade: grade)
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
    /// 점수 등급 → 다람이 일러스트 매핑.
    init(grade: ReportCardModel.Grade) {
        switch grade {
        case .good: self = Bool.random() ? .champ : .happy
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
    var title: String = "데이터가 부족해요"
    var subtitle: String = "식사 시간이 너무 짧거나, AirPods IMU 신호를 받지 못해\n이번 식사의 분석을 만들지 못했어요."

    var body: some View {
        VStack(spacing: 14) {
            Text(emoji).font(.appFont(.regular, size: 48))
            Text(title)
                .font(.appFont(.heavy, size: 18))
                .foregroundStyle(Color.ink800)
            Text(subtitle)
                .font(.appFont(.regular, size: 13))
                .foregroundStyle(Color.ink600)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 24)
        .background(
            LinearGradient(
                colors: [Color.acorn50, .cream, Color.sage50],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .neuoShadow(.md)
    }
}

// MARK: - 점수 산식 팝오버 (info 버튼 → 작은 말풍선)

/// 점수가 어떻게 산출됐는지 4요소 산식을 짧게 풀어 보여주는 작은 팝오버.
/// 카드 그리드 상단의 info 버튼에서 호출. iPhone에서도 sheet로 fallback 안 되게
/// presentationCompactAdaptation(.popover)을 강제해 트리거 버튼 옆 말풍선으로 뜬다.
private struct ScoreFormulaPopover: View {
    let model: ReportCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            formulaRow(label: "속도",      detail: "28회/분",       subScore: model.speedScore)
            formulaRow(label: "리듬",      detail: "씹기 비율 50%+", subScore: model.rhythmScore)
            formulaRow(label: "연속성",    detail: "200회+",         subScore: model.continuityScore)
            formulaRow(label: "식사 시간", detail: "12분 부근",      subScore: model.lengthScore)
        }
        .padding(14)
        .frame(width: 220)
    }

    private func formulaRow(label: String, detail: String, subScore: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.appFont(.bold, size: 12))
                .foregroundStyle(Color.ink800)
                .frame(width: 56, alignment: .leading)
            Text(detail)
                .font(.appFont(.regular, size: 11))
                .foregroundStyle(Color.ink400)
            Spacer(minLength: 0)
            Text("\(subScore)")
                .font(.appFont(.heavy, size: 14))
                .foregroundStyle(Color.ink800)
                .monospacedDigit()
        }
    }
}
