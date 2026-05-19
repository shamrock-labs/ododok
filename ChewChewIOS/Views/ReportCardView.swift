import SwiftUI

/// 식사 후 분석 리포트 카드의 표시 모델. `ChewingSessionDTO` → 이 모델로 변환하는
/// 매퍼는 종료 후 표시(commit ②)에서 추가한다. UI 컴포넌트가 DTO 변경에 직접 결합되지
/// 않도록 분리.
struct ReportCardModel: Equatable {
    /// 식사 점수 0~100.
    let score: Int
    /// 점수 등급. 컬러/라벨 분기.
    let grade: Grade
    /// 4대 지표.
    let chewCount: Int
    let totalDurationSec: Double
    let chewsPerMinute: Double
    /// 만족 표정 0~5 (PRD #3 — 점수가 아니라 5단계 표정 척도). 표시는 "n/5".
    let satisfaction: Int
    /// 한 줄 캡션. nil이면 기본 멘트 fallback.
    let caption: String?
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

/// 식사 후 분석 리포트 카드. 식사 종료 직후 sheet/overlay 표시(commit ②)와
/// 캘린더에서 과거 세션 재현(commit ④) 양쪽에서 동일하게 사용된다. 1080×1920 PNG
/// 공유(commit ③)도 같은 View를 ImageRenderer로 렌더.
struct ReportCardView: View {
    let model: ReportCardModel

    var body: some View {
        VStack(spacing: 18) {
            header
            scoreSection
            metricsGrid
            captionSection
            footer
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
            Text("🌰").font(.appFont(.regular, size: 28))
        }
    }

    private var scoreSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(model.score)")
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

    private var metricsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            metric(label: "씹기 횟수", value: model.chewCount.koLocale, unit: "회")
            metric(label: "총 시간",  value: formatDurationShort(model.totalDurationSec), unit: nil)
            metric(label: "분당 속도", value: String(format: "%.0f", model.chewsPerMinute), unit: "회/분")
            metric(label: "만족도",   value: "\(model.satisfaction)", unit: "/5")
        }
    }

    private func metric(label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.appFont(.medium, size: 11))
                .foregroundStyle(Color.ink400)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.appFont(.heavy, size: 22))
                    .foregroundStyle(Color.ink800)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.appFont(.bold, size: 12))
                        .foregroundStyle(Color.acorn600)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
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

    private var footer: some View {
        HStack {
            Spacer()
            Text("다람이 · chewchew.app")
                .font(.appFont(.medium, size: 10))
                .foregroundStyle(Color.ink400)
        }
    }

    private var gradeColor: Color {
        switch model.grade {
        case .good: Color.sage600
        case .soso: Color.butter500
        case .bad:  Color.blush400
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
            satisfaction: 4,
            caption: "오늘은 천천히 잘 씹었어요. 한 입에 30회 목표 달성!",
            endedAt: Date()
        ))
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
            satisfaction: 3,
            caption: nil,
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
            satisfaction: 2,
            caption: "조금 빨리 먹은 것 같아요. 다음 식사엔 한 입 30회를 의식해 봐요.",
            endedAt: Date()
        ))
        .padding(20)
    }
}

// MARK: - ChewingSessionDTO → ReportCardModel mapper
//
// UI 레이어가 DTO 변경에 직접 결합되지 않도록 카드용 변환 진입점만 이 extension에서
// 노출. 점수 산출은 `SessionScore.compute(_:)`에 위임.

extension ReportCardModel {
    /// `ChewingSessionDTO` → 카드 모델. 분석 5필드가 채워진 세션에서만 nil 아닌 값을
    /// 반환. nil이면 호출자가 빈 상태 카드를 표시 (PRD #3 "데이터가 부족해요").
    static func from(_ dto: ChewingSessionDTO) -> ReportCardModel? {
        guard let score = SessionScore.compute(dto) else { return nil }
        let mins = max(0.001, dto.durationSec / 60)
        let chews = dto.estimatedTotalChews ?? 0
        let chewsPerMin = Double(chews) / mins
        // 만족 표정 0~5 — PRD가 산출식을 명시하지 않아 잠정적으로 점수에 단조 매핑.
        // 후속 PR에서 사용자 피드백 입력으로 분리될 여지.
        let satisfaction = max(0, min(5, Int((Double(score.total) / 20.0).rounded())))
        return ReportCardModel(
            score: score.total,
            grade: Grade(scoreGrade: score.grade),
            chewCount: chews,
            totalDurationSec: dto.durationSec,
            chewsPerMinute: chewsPerMin,
            satisfaction: satisfaction,
            caption: nil,
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
