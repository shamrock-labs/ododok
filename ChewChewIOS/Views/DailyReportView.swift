import SwiftUI

/// 선택한 하루의 모든 세션을 종합한 일간 리포트 표시 모델.
///
/// 단건 세션 카드(`ReportCardModel`)와 달리, 하루치 끼니들을 집계해 "오늘 하루"를
/// 한 장으로 요약한다. 실서비스에 가짜 데이터를 절대 넣지 않는다 — 리포트 가능한
/// 세션이 하나도 없으면 `from(date:sessions:previousSessions:)`가 nil을 돌려
/// 호출자가 빈 상태를 표시한다.
struct DailyReportModel {
    let date: Date

    // 1·2. 한 줄 결론 + 하루 상태/점수
    let headline: String
    let dayScore: Int
    let grade: ReportCardModel.Grade
    let accent: Color

    // 3. 기록 완성도 (주요 3끼 기준)
    let recordedMainSlots: Int           // 0~3
    let mainSlotStates: [(slot: DayMealSlot, recorded: Bool)]

    // 4. 4대 지표 (하루 합계 / 가중평균)
    let sessionCount: Int
    let mealCount: Int                   // 기록된 끼니 슬롯 수(야식 포함)
    let totalChews: Int
    let totalDurationSec: Double
    let avgChewsPerMinute: Double
    let avgChewingFraction: Double

    // 5. 끼니별 비교 (기록된 슬롯만, 슬롯 순서)
    let mealSummaries: [MealSummary]

    // 6·7. 베스트 / 워스트 끼니
    let bestMeal: MealSummary?
    let worstMeal: MealSummary?

    // 8. 어제 대비 변화
    let yesterday: YesterdayDelta

    // 9·10·11. 원인 해석 / 내일 목표 / 코치
    let causeText: String
    let tomorrowGoal: String
    let coachMood: Mood
    let coachMessage: String

    // 12. 데이터 신뢰 상태
    let trust: Trust

    /// 한 끼(슬롯) 단위 집계. 같은 슬롯에 여러 세션이면 합산하고 점수는 평균낸다.
    struct MealSummary: Identifiable {
        let id: UUID                     // 대표 세션 id
        let slot: DayMealSlot
        let sessionCount: Int
        let chews: Int
        let durationSec: Double
        let score: Int
        let chewsPerMinute: Double
        let chewingFraction: Double
        let representative: ChewingSessionDTO   // 슬롯 최고 점수 세션 — 탭하면 단건 상세
        var label: String { slot.label }
    }

    struct YesterdayDelta {
        enum State { case noData, compared }
        let state: State
        let chewDelta: Int               // 한 끼 평균 저작 델타
        let scoreDelta: Int
        let text: String
    }

    enum Trust {
        case high, medium, low

        var badge: String {
            switch self {
            case .high:   "신뢰 양호"
            case .medium: "참고용"
            case .low:    "신호 약함"
            }
        }
        // 데이터 신뢰는 성과(valence)가 아니라 메타 정보 — 좋음=중립, 낮음=주의(butter)만.
        // sage/blush는 상태 전용이라 여기 쓰지 않는다.
        var color: Color {
            switch self {
            case .high:   .textSecondary
            case .medium: .butter600
            case .low:    .butter600
            }
        }
    }
}

// MARK: - 집계

extension DailyReportModel {
    /// 하루치 세션을 종합 모델로. 리포트 가능 세션(분석 5필드 충족)이 0개면 nil.
    /// `previousSessions`는 어제(혹은 직전 날) 세션 — 어제 대비 비교에만 쓴다.
    static func from(
        date: Date,
        sessions: [ChewingSessionDTO],
        previousSessions: [ChewingSessionDTO]
    ) -> DailyReportModel? {
        let entries = sessions.compactMap(DailyEntry.init).sorted { $0.startedAt < $1.startedAt }
        guard !entries.isEmpty else { return nil }

        let count = entries.count
        let totalChews = entries.reduce(0) { $0 + $1.model.chewCount }
        let totalDuration = entries.reduce(0.0) { $0 + $1.model.totalDurationSec }
        let totalChewSec = entries.reduce(0.0) { $0 + $1.model.chewingSeconds }
        let totalRestSec = entries.reduce(0.0) { $0 + $1.model.restSeconds }

        let avgCpm = totalDuration > 0 ? Double(totalChews) / (totalDuration / 60) : 0
        let fracDenom = totalChewSec + totalRestSec
        let avgFraction = fracDenom > 0
            ? totalChewSec / fracDenom
            : entries.map(\.model.chewingFraction).reduce(0, +) / Double(count)

        let dayScore = roundedMean(entries.map(\.model.score))
        let grade: ReportCardModel.Grade = dayScore >= 80 ? .good : (dayScore >= 60 ? .soso : .bad)
        let accent: Color = {
            switch grade {
            case .good: .sage600
            case .soso: .butter600
            case .bad:  .blush500
            }
        }()

        // 슬롯 집계
        let grouped = Dictionary(grouping: entries, by: \.slot)
        let slotOrder: [DayMealSlot] = [.morning, .lunch, .dinner, .lateNight]
        let mealSummaries: [MealSummary] = slotOrder.compactMap { slot in
            guard let group = grouped[slot], !group.isEmpty else { return nil }
            let chews = group.reduce(0) { $0 + $1.model.chewCount }
            let dur = group.reduce(0.0) { $0 + $1.model.totalDurationSec }
            let cs = group.reduce(0.0) { $0 + $1.model.chewingSeconds }
            let rs = group.reduce(0.0) { $0 + $1.model.restSeconds }
            let denom = cs + rs
            let frac = denom > 0 ? cs / denom : group.map(\.model.chewingFraction).reduce(0, +) / Double(group.count)
            // 대표 세션 = 그 슬롯에서 가장 점수 높은 세션(탭 → 단건 상세).
            let rep = group.max { $0.model.score < $1.model.score }!
            return MealSummary(
                id: rep.dto.id,
                slot: slot,
                sessionCount: group.count,
                chews: chews,
                durationSec: dur,
                score: roundedMean(group.map(\.model.score)),
                chewsPerMinute: dur > 0 ? Double(chews) / (dur / 60) : 0,
                chewingFraction: frac,
                representative: rep.dto
            )
        }

        let bestMeal = mealSummaries.max { $0.score < $1.score }
        let worstMeal = mealSummaries.count > 1 ? mealSummaries.min { $0.score < $1.score } : nil

        // 기록 완성도 (주요 3끼)
        let mainSlots: [DayMealSlot] = [.morning, .lunch, .dinner]
        let recordedSlots = Set(entries.map(\.slot))
        let mainStates = mainSlots.map { (slot: $0, recorded: recordedSlots.contains($0)) }
        let recordedMain = mainStates.filter(\.recorded).count
        let mealCount = recordedSlots.count

        // 4축 평균 → 최약축 → 원인/목표
        let speed = roundedMean(entries.map(\.model.speedScore))
        let rhythm = roundedMean(entries.map(\.model.rhythmScore))
        let continuity = roundedMean(entries.map(\.model.continuityScore))
        let length = roundedMean(entries.map(\.model.lengthScore))
        let weakest = [
            (Axis.speed, speed), (.rhythm, rhythm), (.continuity, continuity), (.length, length),
        ].min { $0.1 < $1.1 }!.0

        // 어제 대비
        let yesterday = makeYesterdayDelta(
            todayPerMeal: count == 0 ? 0 : totalChews / count,
            todayScore: dayScore,
            previousSessions: previousSessions
        )

        // 데이터 신뢰
        let hasModel = entries.allSatisfy { $0.dto.modelVersion != nil }
        let goodSignal = entries.allSatisfy { $0.dto.sampleRateHz > 0 && $0.dto.sampleCount > 50 }
        let trust: Trust = (hasModel && goodSignal) ? .high : ((hasModel || goodSignal) ? .medium : .low)

        let coachMood: Mood = {
            switch grade {
            case .good: dayScore >= 90 ? .champ : .happy
            case .soso: .puffy
            case .bad:  .sleepy
            }
        }()

        return DailyReportModel(
            date: date,
            headline: makeHeadline(grade: grade, recordedMain: recordedMain),
            dayScore: dayScore,
            grade: grade,
            accent: accent,
            recordedMainSlots: recordedMain,
            mainSlotStates: mainStates,
            sessionCount: count,
            mealCount: mealCount,
            totalChews: totalChews,
            totalDurationSec: totalDuration,
            avgChewsPerMinute: avgCpm,
            avgChewingFraction: avgFraction,
            mealSummaries: mealSummaries,
            bestMeal: bestMeal,
            worstMeal: worstMeal,
            yesterday: yesterday,
            causeText: weakest.causeText,
            tomorrowGoal: weakest.goalText,
            coachMood: coachMood,
            coachMessage: makeCoachMessage(grade: grade),
            trust: trust
        )
    }

    /// 식사 흐름 4요소. 최약축이 원인 해석과 내일 목표를 결정한다.
    enum Axis {
        case speed, rhythm, continuity, length

        var causeText: String {
            switch self {
            case .speed:      "분당 저작 속도가 권장보다 빠른 끼니가 있었어요. 처음 몇 입이 빠르면 전체 흐름도 따라가요."
            case .rhythm:     "씹기보다 쉬는 시간 비율이 길었어요. 한 입을 끝까지 씹기 전에 다음 입으로 넘어간 끼니가 있어요."
            case .continuity: "한 끼 저작 횟수가 권장보다 적었어요. 짧게 끝낸 끼니가 하루 평균을 낮췄어요."
            case .length:     "식사 시간이 짧아 빠르게 끝난 끼니가 있었어요. 시간이 짧으면 충분히 씹기 어려워요."
            }
        }
        var goalText: String {
            switch self {
            case .speed:      "내일은 첫 5분만 의식적으로 속도를 낮춰 시작해봐요."
            case .rhythm:     "내일은 한 입을 끝까지 씹고 삼킨 뒤 다음 입을 떠봐요."
            case .continuity: "내일은 한 끼 300회를 목표로 조금 더 씹어봐요."
            case .length:     "내일은 한 끼를 12분까지 천천히 늘려봐요."
            }
        }
    }
}

// MARK: - 집계 보조 (private)

/// 하루 집계의 내부 1세션 단위. DTO + 카드 모델 + 끼니 슬롯을 묶는다.
private struct DailyEntry {
    let dto: ChewingSessionDTO
    let model: ReportCardModel
    let slot: DayMealSlot
    var startedAt: Date { dto.startedAt }

    init?(_ dto: ChewingSessionDTO) {
        guard let model = ReportCardModel.from(dto) else { return nil }
        self.dto = dto
        self.model = model
        self.slot = DayMealSlot(hour: mealCalendarCalendar.component(.hour, from: dto.startedAt))
    }
}

private func roundedMean(_ values: [Int]) -> Int {
    guard !values.isEmpty else { return 0 }
    return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
}

private func makeHeadline(grade: ReportCardModel.Grade, recordedMain: Int) -> String {
    switch grade {
    case .good:
        return recordedMain >= 3
            ? "세 끼 모두 천천히 잘 씹은 하루예요"
            : "기록한 끼니를 알차게 잘 씹은 하루예요"
    case .soso:
        return "리듬은 괜찮았던 하루예요. 한 끼만 더 신경 쓰면 좋아져요"
    case .bad:
        return "조금 빠르게 지나간 하루예요. 내일은 한 끼라도 천천히 먹어봐요"
    }
}

private func makeCoachMessage(grade: ReportCardModel.Grade) -> String {
    switch grade {
    case .good: "오늘처럼 천천히 씹는 리듬을 내일도 이어가요. 다람이가 옆에서 응원할게요."
    case .soso: "전반적으로 무난했어요. 가장 아쉬웠던 한 끼만 보완하면 충분히 좋아져요."
    case .bad:  "오늘은 조금 바빴죠. 내일은 한 끼라도 첫 5분을 천천히 시작해봐요."
    }
}

private func makeYesterdayDelta(
    todayPerMeal: Int,
    todayScore: Int,
    previousSessions: [ChewingSessionDTO]
) -> DailyReportModel.YesterdayDelta {
    let prev = previousSessions.compactMap { ReportCardModel.from($0) }
    guard !prev.isEmpty else {
        return .init(state: .noData, chewDelta: 0, scoreDelta: 0, text: "어제는 기록이 없어 비교할 수 없어요.")
    }
    let prevPerMeal = prev.reduce(0) { $0 + $1.chewCount } / prev.count
    let prevScore = roundedMean(prev.map(\.score))
    let chewDelta = todayPerMeal - prevPerMeal
    let scoreDelta = todayScore - prevScore

    let chewPhrase: String
    if abs(chewDelta) < 20 {
        chewPhrase = "어제와 비슷한 양을 씹었어요"
    } else if chewDelta > 0 {
        chewPhrase = "어제보다 한 끼에 약 \(chewDelta.koLocale)회 더 씹었어요"
    } else {
        chewPhrase = "어제보다 한 끼에 약 \(abs(chewDelta).koLocale)회 덜 씹었어요"
    }
    let scorePhrase: String
    if scoreDelta == 0 {
        scorePhrase = "점수는 그대로예요"
    } else {
        scorePhrase = scoreDelta > 0 ? "점수도 \(scoreDelta)점 올랐어요" : "점수는 \(abs(scoreDelta))점 내렸어요"
    }
    return .init(state: .compared, chewDelta: chewDelta, scoreDelta: scoreDelta, text: "\(chewPhrase). \(scorePhrase).")
}

// MARK: - View

/// 기록탭 "일간 리포트" 진입 화면. 선택한 날의 모든 세션을 종합해 한 장으로 보여준다.
/// 디자인은 단건 `ReportCardView`와 같은 시스템(흰 카드·rounded 24·softShadow·
/// acorn/sage/butter/blush/ink·AppFont)을 따른다. 끼니별 비교 행을 탭하면 그 끼니의
/// 단건 세션 상세(`SessionReportDetailView`)로 push 한다.
struct DailyReportView: View {
    let date: Date
    let sessions: [ChewingSessionDTO]
    let previousSessions: [ChewingSessionDTO]

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    private var model: DailyReportModel? {
        DailyReportModel.from(date: date, sessions: sessions, previousSessions: previousSessions)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let model {
                        content(model)
                    } else {
                        EmptyReportCardView(
                            title: "이 날은 일간 리포트가 없어요",
                            subtitle: "분석된 식사 기록이 없어요. 식사를 기록하면 하루 종합 리포트가 만들어져요."
                        )
                    }
                }
                // 식사 리포트(SessionReportDetailView)와 동일한 좌우/상하 마진으로 통일.
                .padding(.horizontal, AppSpacing.pageInsetCompact)
                .padding(.vertical, AppSpacing.pageInsetVertical)
            }
            .background(Color.pageBackground.ignoresSafeArea())
            .navigationTitle("일간 리포트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .font(.appFont(.boldBody))
                        .foregroundStyle(Color.textAction)
                }
            }
            .navigationDestination(for: DailyReportModel.MealSummary.ID.self) { id in
                if let dto = sessions.first(where: { $0.id == id }) {
                    SessionReportDetailView(dto: dto)
                }
            }
            .task {
                trackDailyReportOpened()
            }
        }
    }

    private func content(_ model: DailyReportModel) -> some View {
        // 카드 남발 금지(CLAUDE.md) — 완성도+지표를 '하루 요약'으로, 베스트/아쉬움+비교를
        // '끼니'로 묶어 떠 있는 카드 수를 줄인다. 오늘의 해석·내일의 목표·다람이 코치는
        // UI에서 임시 제외(로직 유지, 추후 수정 예정).
        VStack(spacing: 16) {
            conclusionCard(model)
            summarySection(model)
            mealsSection(model)
            yesterdayCard(model)
            trustFooter(model)
        }
    }

    // MARK: 1·2. 한 줄 결론 + 하루 상태/점수

    private func conclusionCard(_ model: DailyReportModel) -> some View {
        AppCard(
            padding: AppSpacing.sectionGap,
            radius: AppRadius.lg,
            background: model.accent.opacity(0.08)
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.gap) {
                Text(headerDateLabel)
                    .font(.appFont(.semiboldCallout))
                    .foregroundStyle(Color.textMuted)

                // 한마디 헤더·등급 배지는 제거 — 아래 한 줄 문구가 그 역할을 한다. 문장 단위로 줄바꿈.
                Text(model.headline.replacingOccurrences(of: ". ", with: ".\n"))
                    .font(.appFont(.heavyTitle))
                    .foregroundStyle(Color.textDefault)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("오늘 점수")
                        .font(.appFont(.boldCallout))
                        .foregroundStyle(Color.textMuted)
                    Spacer(minLength: 0)
                    Text("\(model.dayScore)")
                        .font(.appFont(.heavyDisplay))
                        .foregroundStyle(model.accent)
                        .monospacedDigit()
                    Text("/ 100")
                        .font(.appFont(.boldCaption))
                        .foregroundStyle(Color.textSubtle)
                }
            }
        }
    }

    // MARK: 3·4. 하루 요약 — 기록 완성도 + 4대 지표(총 저작·식사시간·평균 속도·씹기 비율)

    private func summarySection(_ model: DailyReportModel) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.cardH) {
                HStack(alignment: .firstTextBaseline) {
                    Text("오늘 요약")
                        .font(.appFont(.sectionTitle))
                        .foregroundStyle(Color.textDefault)
                    Spacer(minLength: 0)
                    Text("\(model.recordedMainSlots)/3끼")
                        .font(.appFont(.heavyCaption))
                        .foregroundStyle(model.recordedMainSlots == 3 ? Color.statusSuccess : Color.textMuted)
                        .monospacedDigit()
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            model.recordedMainSlots == 3 ? Color.statusSuccess.opacity(0.14) : Color.bgSunken,
                            in: Capsule()
                        )
                }
                HStack(spacing: 8) {
                    ForEach(model.mainSlotStates, id: \.slot) { state in
                        slotChip(slot: state.slot, recorded: state.recorded)
                    }
                }
                // 지표 4종은 색으로 구분하지 않는다(색=상태 전용). 라벨로만 식별, 수치는 중립색.
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    metricCell(
                        label: "총 저작",
                        value: "\(model.totalChews.koLocale)회",
                        sub: "\(model.mealCount)끼 합산"
                    )
                    metricCell(
                        label: "총 식사시간",
                        value: durationLabel(model.totalDurationSec),
                        sub: "한 끼 평균 \(perMealMinutes(model))분"
                    )
                    metricCell(
                        label: "평균 속도",
                        value: "약 \(Int(model.avgChewsPerMinute.rounded()))회/분",
                        sub: "권장 28회/분"
                    )
                    metricCell(
                        label: "씹기 비율",
                        value: "\(Int((model.avgChewingFraction * 100).rounded()))%",
                        sub: "권장 60%"
                    )
                }
            }
        }
    }

    // 끼니 슬롯은 색으로 구분하지 않는다(색=상태 전용). 아이콘 형태 + 라벨로만 식별하고,
    // 기록/미기록은 색조가 아니라 진하기(중립색의 농도)로 표현한다.
    private func slotChip(slot: DayMealSlot, recorded: Bool) -> some View {
        VStack(spacing: AppSpacing.oneHalf) {
            OpenIconView(
                icon: slot.openIcon,
                color: recorded ? Color.textMuted : Color.textSubtle.opacity(0.5),
                lineWidth: 2.1
            )
            .frame(width: AppSpacing.inputH, height: AppSpacing.inputH)
            Text(slot.label)
                .font(.appFont(.boldCaption))
                .foregroundStyle(recorded ? Color.textDefault : Color.textSubtle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.three)
        .background(
            recorded ? Color.bgSunken : Color.borderDefault.opacity(0.5),
            in: RoundedRectangle(cornerRadius: AppRadius.element)
        )
    }

    private func metricCell(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.oneHalf) {
            Text(label)
                .font(.appFont(.semiboldCallout))
                .foregroundStyle(Color.textMuted)
            Text(value)
                .font(.appFont(.heavyTitle))
                .foregroundStyle(Color.textDefault)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(sub)
                .font(.appFont(.semiboldCaption))
                .foregroundStyle(Color.textMuted.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.cell)
        .background(Color.bgSunken.opacity(0.6), in: RoundedRectangle(cornerRadius: AppRadius.container))
    }

    // MARK: 5·6·7. 끼니 — 베스트/아쉬움 + 아침·점심·저녁 끼니별 비교

    private func mealsSection(_ model: DailyReportModel) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.three) {
                Text("끼니")
                    .font(.appFont(.heavyBody))
                    .foregroundStyle(Color.textDefault)
                // 베스트/아쉬움 행을 탭하면 그 끼니의 세션 리포트로 이동.
                if let best = model.bestMeal {
                    NavigationLink(value: best.id) {
                        highlightRow(
                            tag: "베스트",
                            tagColor: .sage600,
                            meal: best,
                            note: "가장 안정적으로 씹은 끼니예요."
                        )
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        trackMealReportOpened(best.representative)
                    })
                    .buttonStyle(.plain)
                }
                if let worst = model.worstMeal {
                    NavigationLink(value: worst.id) {
                        highlightRow(
                            tag: "아쉬움",
                            tagColor: .blush500,
                            meal: worst,
                            note: "다음엔 이 끼니부터 천천히 시작해봐요."
                        )
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        trackMealReportOpened(worst.representative)
                    })
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func mealRow(_ meal: DailyReportModel.MealSummary, maxChews: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.two) {
            HStack(spacing: AppSpacing.inner) {
                // 끼니 식별은 아이콘만(색 중립). 막대는 acorn 단일 톤으로 값만 비교.
                OpenIconView(icon: meal.slot.openIcon, color: Color.textMuted, lineWidth: 2.1)
                    .frame(width: AppSpacing.four, height: AppSpacing.four)
                    .frame(width: AppSize.iconContainerCompact, height: AppSize.iconContainerCompact)
                    .background(Color.bgSunken, in: RoundedRectangle(cornerRadius: AppRadius.inner))
                Text(meal.label)
                    .font(.appFont(.heavyBody))
                    .foregroundStyle(Color.textDefault)
                if meal.sessionCount > 1 {
                    Text("\(meal.sessionCount)회")
                        .font(.appFont(.boldMicro))
                        .foregroundStyle(Color.textSubtle)
                }
                Spacer(minLength: 0)
                Text("\(meal.score)점")
                    .font(.appFont(.heavyCallout))
                    .foregroundStyle(Color.textDefault)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.borderDefault)
                    Capsule()
                        .fill(Color.acorn500)
                        .frame(width: max(8, geo.size.width * CGFloat(meal.chews) / CGFloat(maxChews)))
                }
            }
            .frame(height: AppSpacing.two)
            Text("\(meal.chews.koLocale)회 · \(durationLabel(meal.durationSec)) · 약 \(Int(meal.chewsPerMinute.rounded()))회/분")
                .font(.appFont(.semiboldCaption))
                .foregroundStyle(Color.textMuted)
                .monospacedDigit()
        }
        .padding(AppSpacing.three)
        .background(Color.bgSunken.opacity(0.6), in: RoundedRectangle(cornerRadius: AppRadius.md))
    }

    private func highlightRow(tag: String, tagColor: Color, meal: DailyReportModel.MealSummary, note: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.three) {
            // 끼니 아이콘은 중립 — 좋음/아쉬움 구분은 태그(상태색)가 전담한다.
            OpenIconView(icon: meal.slot.openIcon, color: Color.textMuted, lineWidth: 2.1)
                .frame(width: AppSpacing.inputH, height: AppSpacing.inputH)
                .frame(width: AppSpacing.nine, height: AppSpacing.nine)
                .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: AppSpacing.three))
            VStack(alignment: .leading, spacing: AppSpacing.microGap) {
                HStack(spacing: AppSpacing.oneHalf) {
                    Text(tag)
                        .font(.appFont(.heavyMicro))
                        .foregroundStyle(tagColor)
                        .padding(.horizontal, AppSpacing.badgeH)
                        .padding(.vertical, AppSpacing.badgeV)
                        .background(tagColor.opacity(0.14), in: Capsule())
                    Text("\(meal.label) · \(meal.score)점")
                        .font(.appFont(.heavyLabel))
                        .foregroundStyle(Color.textDefault)
                        .monospacedDigit()
                }
                Text(note)
                    .font(.appFont(.semiboldCaption))
                    .foregroundStyle(Color.textMuted)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.appFont(.boldMicro))
                .foregroundStyle(Color.textSubtle)
        }
        .padding(AppSpacing.three)
        .background(tagColor.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.md))
    }

    // MARK: 8. 어제 대비 변화

    private func yesterdayCard(_ model: DailyReportModel) -> some View {
        let glyph = yesterdayGlyph(model.yesterday)
        return AppCard {
            HStack(alignment: .top, spacing: AppSpacing.three) {
                Image(systemName: glyph.icon)
                    .font(.appFont(.boldCallout))
                    .foregroundStyle(glyph.tint)
                    .frame(width: AppSize.iconContainer, height: AppSize.iconContainer)
                    .background(glyph.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.iconContainer))
                VStack(alignment: .leading, spacing: AppSpacing.microGap) {
                    Text("어제 대비 변화")
                        .font(.appFont(.heavyBody))
                        .foregroundStyle(Color.textDefault)
                    Text(model.yesterday.text)
                        .font(.appFont(.semiboldCallout))
                        .foregroundStyle(Color.textMuted)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// 어제 대비 방향을 상태색 + 화살표로 표현(색만으로 의미 전달 금지 → 아이콘 병행).
    /// 좋아짐=accentGood(↗) · 나빠짐=accentWarn(↘) · 같음/없음=중립(—).
    private func yesterdayGlyph(_ delta: DailyReportModel.YesterdayDelta) -> (icon: String, tint: Color) {
        guard delta.state == .compared else { return ("minus", .textTertiary) }
        if delta.scoreDelta > 0 { return ("arrow.up.right", .accentGood) }
        if delta.scoreDelta < 0 { return ("arrow.down.right", .accentWarn) }
        return ("equal", .textTertiary)
    }

    // MARK: 9·10. 오늘의 원인 해석 + 내일의 목표

    private func interpretationCard(_ model: DailyReportModel) -> some View {
        AppCard(padding: AppSpacing.cardContent, background: Color.statusSuccessMuted.opacity(0.72)) {
            VStack(alignment: .leading, spacing: AppSpacing.three) {
            interpretationRow(
                icon: "magnifyingglass",
                title: "오늘의 해석",
                body: model.causeText,
                tint: .acorn700
            )
            Divider().background(Color.hairline)
            interpretationRow(
                icon: "target",
                title: "내일의 목표",
                body: model.tomorrowGoal,
                tint: .sage600
            )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg).stroke(Color.statusSuccessBorder, lineWidth: AppSize.border)
        )
    }

    private func interpretationRow(icon: String, title: String, body: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.inner) {
            Image(systemName: icon)
                .font(.appFont(.boldCallout))
                .foregroundStyle(tint)
                .frame(width: AppSize.iconContainerTiny, height: AppSize.iconContainerTiny)
                .background(Color.bgSurface.opacity(0.75), in: Circle())
            VStack(alignment: .leading, spacing: AppSpacing.microGap) {
                Text(title)
                    .font(.appFont(.heavyLabel))
                    .foregroundStyle(Color.textDefault)
                Text(body)
                    .font(.appFont(.semiboldCallout))
                    .foregroundStyle(Color.textMuted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 11. 다람이 코치 피드백

    private func coachCard(_ model: DailyReportModel) -> some View {
        AppCard(padding: AppSpacing.cell, background: Color.statusSuccessMuted.opacity(0.82)) {
            HStack(alignment: .top, spacing: AppSpacing.three) {
            Image(model.coachMood.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: Metrics.coachAvatar, height: Metrics.coachAvatar)
                .background(Color.statusWarningMuted.opacity(0.7), in: Circle())
            VStack(alignment: .leading, spacing: AppSpacing.microLabelGap) {
                Text("다람이 코치")
                    .font(.appFont(.heavyBody))
                    .foregroundStyle(Color.textDefault)
                Text(model.coachMessage)
                    .font(.appFont(.semiboldCallout))
                    .foregroundStyle(Color.textMuted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg).stroke(Color.statusSuccessBorder, lineWidth: AppSize.border)
        )
    }

    // MARK: 12. 데이터 신뢰 상태

    private func trustFooter(_ model: DailyReportModel) -> some View {
        HStack(spacing: AppSpacing.two) {
            Image(systemName: "checkmark.seal.fill")
                .font(.appFont(.boldCaption))
                .foregroundStyle(model.trust.color)
            Text("데이터 신뢰")
                .font(.appFont(.boldCaption))
                .foregroundStyle(Color.textMuted)
            Text(model.trust.badge)
                .font(.appFont(.heavyMicro))
                .foregroundStyle(model.trust.color)
                .padding(.horizontal, AppSpacing.badgeH)
                .padding(.vertical, AppSpacing.badgeV)
                .background(model.trust.color.opacity(0.14), in: Capsule())
            Spacer(minLength: 0)
            Text("분석 \(model.sessionCount)끼")
                .font(.appFont(.semiboldCaption))
                .foregroundStyle(Color.textSubtle)
                .monospacedDigit()
        }
        .padding(.horizontal, AppSpacing.cell)
        .padding(.vertical, AppSpacing.three)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSunken.opacity(0.6), in: RoundedRectangle(cornerRadius: AppRadius.md))
    }

    // MARK: - 보조

    private var headerDateLabel: String {
        KoDate.string(date, "M월 d일 EEEE")
    }

    private func perMealMinutes(_ model: DailyReportModel) -> Int {
        guard model.sessionCount > 0 else { return 0 }
        return max(1, Int((model.totalDurationSec / Double(model.sessionCount) / 60).rounded()))
    }

    private func durationLabel(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let mins = total / 60
        let secs = total % 60
        if mins == 0 { return "\(secs)초" }
        if secs == 0 { return "\(mins)분" }
        return "\(mins)분 \(secs)초"
    }

    private func trackDailyReportOpened() {
        state.analytics.track(.dailyReportOpened(
            selectedDate: analyticsDateString(date),
            daysFromToday: daysFromToday(date),
            mealCount: model?.mealCount ?? 0,
            sessionCount: model?.sessionCount ?? sessions.count,
            dayScore: model?.dayScore,
            grade: model?.grade.analyticsValue
        ))
    }

    private func trackMealReportOpened(_ session: ChewingSessionDTO) {
        let sessionDate = mealCalendarCalendar.startOfDay(for: session.startedAt)
        let slot = DayMealSlot(hour: mealCalendarCalendar.component(.hour, from: session.startedAt))
        let score = ReportCardModel.from(session)?.score
        state.analytics.track(.mealReportOpened(
            source: "daily_report",
            selectedDate: analyticsDateString(sessionDate),
            daysFromToday: daysFromToday(sessionDate),
            mealSlot: slot.analyticsValue,
            score: score,
            estimatedTotalChews: session.estimatedTotalChews,
            durationSec: Int(session.durationSec.rounded())
        ))
    }

    private func analyticsDateString(_ date: Date) -> String {
        KoDate.string(date, "yyyy-MM-dd")
    }

    private func daysFromToday(_ date: Date) -> Int {
        let today = mealCalendarCalendar.startOfDay(for: Date())
        let normalizedDate = mealCalendarCalendar.startOfDay(for: date)
        return mealCalendarCalendar.dateComponents([.day], from: today, to: normalizedDate).day ?? 0
    }
}

private extension ReportCardModel.Grade {
    var analyticsValue: String {
        switch self {
        case .good: "good"
        case .soso: "soso"
        case .bad: "bad"
        }
    }
}

private enum Metrics {
    static let coachAvatar = AppSize.visualMedium
}
