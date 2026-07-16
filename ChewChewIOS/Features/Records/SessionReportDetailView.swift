import SwiftUI

/// 기록 지면(ReportHubView)·일간 리포트가 같은 day boundary 동작을 보장하도록 공유하는
/// calendar instance. view마다 각자 생성하면 미세한 차이로 dot/리스트 일관성이 깨질 수 있다.
let mealCalendarCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "ko_KR")
    return calendar
}()

// MARK: - Single session detail (sheet 안 NavigationStack push)

/// 기록 지면에서 여는 단일 세션 리포트 화면.
struct SessionReportDetailView: View {
    private let model: ReportCardModel?
    private let unavailableContent: MealReportUnavailableContent?

    /// PNG 렌더는 ImageRenderer 호출 비용이 작지 않아 view 진입 시 1회만 만든다.
    /// 빈 상태(분석 5필드 nil) 세션에선 nil로 남아 공유 버튼이 자동 hidden.
    @State private var sharePayload: ReportCardSharePayload?

    init(dto: ChewingSessionDTO) {
        self.model = ReportCardModel.from(dto)
        self.unavailableContent = model == nil ? .from(dto.mealReport) : nil
    }

    var body: some View {
        ScrollView {
            Group {
                if let model {
                    ReportCardView(model: model)
                } else {
                    EmptyReportCardView(
                        emoji: unavailableContent?.emoji ?? "🐿️",
                        title: unavailableContent?.title ?? "리포트를 표시할 수 없어요",
                        subtitle: unavailableContent?.message ?? "저장된 식사 리포트가 없어요."
                    )
                }
            }
            // 식사 리포트 카드를 더 넓게 — 좌우 여백을 줄인다.
            .padding(.horizontal, 10)
            .padding(.vertical, 16)
        }
        .background(Color.pageBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                AppSheetTitleText(title: "식사 리포트")
            }
            if let payload = sharePayload {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: payload, preview: SharePreview("식사 리포트")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .foregroundStyle(Color.acorn600)
                }
            }
        }
        .task {
            guard sharePayload == nil,
                  let model,
                  let data = ReportCardRenderer.render(model)
            else { return }
            sharePayload = ReportCardSharePayload(imageData: data)
        }
    }
}

/// 끼니 슬롯 분류. 시각(시간)으로 매핑. UI 라벨/아이콘 보관.
enum DayMealSlot: CaseIterable, Hashable {
    case morning, lunch, dinner, lateNight

    var label: String {
        switch self {
        case .morning:   "아침"
        case .lunch:     "점심"
        case .dinner:    "저녁"
        case .lateNight: "야식"
        }
    }
    var analyticsValue: String {
        switch self {
        case .morning:   "morning"
        case .lunch:     "lunch"
        case .dinner:    "dinner"
        case .lateNight: "late_night"
        }
    }
    var openIcon: OpenIcon {
        switch self {
        case .morning:   .sunrise
        case .lunch:     .utensils
        case .dinner:    .moonStar
        case .lateNight: .moonStar
        }
    }
    var iconColor: Color {
        switch self {
        case .morning:   .butter600
        case .lunch:     .sage600
        case .dinner:    .blush500
        case .lateNight: .acorn700
        }
    }
    init(hour: Int) {
        switch hour {
        case 6...10:  self = .morning
        case 11...14: self = .lunch
        case 15...21: self = .dinner
        default:      self = .lateNight
        }
    }

    init?(serverSlot: String) {
        switch serverSlot {
        case "BREAKFAST": self = .morning
        case "LUNCH": self = .lunch
        case "DINNER": self = .dinner
        case "OTHER", "LATE_NIGHT": self = .lateNight
        default: return nil
        }
    }
}
