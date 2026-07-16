import SwiftUI

/// 식사 종료 직후 자동으로 표시되는 sheet. 측정 종료 → IMU 업로드/온디바이스
/// 분석이 진행되는 동안 같은 sheet 안에서 "분석 중" 스피너를 먼저 보여주고,
/// `ChewingSessionDTO`가 채워지면 `ReportCardView`로 자연스럽게 전환된다.
/// 분석 5필드가 nil인 세션(시뮬레이터/AirPods 미연결/30초 미만)은 PRD #3의
/// "분석을 만들지 못했어요" 빈 카드로 대체.
struct SessionResultSheet: View {
    let dto: ChewingSessionDTO?
    let isAnalyzing: Bool
    let onClose: () -> Void

    /// PNG 렌더는 ImageRenderer 호출 비용이 작지 않아 sheet 진입 시 1회만 만든다.
    @State private var sharePayload: ReportCardSharePayload?

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let dto {
                        if let model = ReportCardModel.from(dto) {
                            ReportCardView(model: model)
                        } else {
                            let content = MealReportUnavailableContent.from(dto.mealReport)
                            EmptyReportCardView(
                                title: content.title,
                                subtitle: content.message
                            )
                        }
                    } else {
                        analyzingView
                    }
                }
                .padding(AppSpacing.sheetContent)
            }
            .background(Color.bgPage.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    AppSheetTitleText(title: dto == nil ? "분석 중" : "식사 리포트")
                }
                if dto != nil, let payload = sharePayload {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: payload, preview: SharePreview("식사 리포트")) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundStyle(Color.textActionStrong)
                    }
                }
                if dto != nil {
                    // 분석 중에는 닫기 버튼 숨김 — 분석은 보통 수 초 안에 끝나므로
                    // 사용자가 잠깐 기다리도록 유도. 인터랙티브 dismiss도 같이 차단.
                    ToolbarItem(placement: .topBarTrailing) {
                        AppSheetTextActionButton(title: "닫기", action: onClose)
                    }
                }
            }
            .task(id: dto?.id) {
                guard let dto, sharePayload == nil,
                      let model = ReportCardModel.from(dto),
                      let data = ReportCardRenderer.render(model)
                else { return }
                sharePayload = ReportCardSharePayload(imageData: data)
            }
        }
        .interactiveDismissDisabled(dto == nil)
    }

    /// 분석 중 화면 — 스피너 + 안내 문구. 측정 종료 직후 사용자가 잠깐 머무는
    /// 공간이라 정보 밀도는 의도적으로 낮춤.
    private var analyzingView: some View {
        VStack(spacing: AppSpacing.verticalLoose) {
            Spacer(minLength: 48)
            ProgressView()
                .controlSize(.large)
                .tint(Color.dataChew)
            VStack(spacing: AppSpacing.oneHalf) {
                Text("씹기 분석 중이에요")
                    .font(.appFont(.boldBodyLarge))
                    .foregroundStyle(Color.textDefault)
                Text("잠시만요")
                    .font(.appFont(.semiboldBody))
                    .foregroundStyle(Color.textMuted)
            }
            Spacer(minLength: 48)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.eight)
    }
}

struct MealReportUnavailableContent: Equatable {
    let title: String
    let message: String

    static func from(_ report: MealReportDTO?) -> MealReportUnavailableContent {
        guard let report else {
            return .init(
                title: "리포트를 준비하고 있어요",
                message: "서버 리포트를 아직 받지 못했어요. 잠시 후 다시 확인해 주세요."
            )
        }
        guard report.status == .unreportable else {
            return .init(
                title: "리포트를 준비하고 있어요",
                message: "현재 상태의 리포트는 아직 표시할 수 없어요. 잠시 후 다시 확인해 주세요."
            )
        }
        switch report.reason {
        case .sessionTooShort:
            return .init(
                title: "식사 기록이 너무 짧았어요",
                message: "30초 이상 식사하면 리포트를 만들 수 있어요."
            )
        case .analysisMissing:
            return .init(
                title: "씹기 신호를 받지 못했어요",
                message: "AirPods 연결과 센서 신호를 확인한 뒤 다시 기록해 주세요."
            )
        case .invalidAnalysisInput:
            return .init(
                title: "분석값을 확인하지 못했어요",
                message: "이번 식사의 분석값이 올바르지 않아 리포트를 만들지 않았어요."
            )
        case .unsupportedModelVersion:
            return .init(
                title: "아직 지원하지 않는 분석이에요",
                message: "앱을 최신 버전으로 업데이트한 뒤 다시 확인해 주세요."
            )
        case .unknown, .none:
            return .init(
                title: "리포트를 준비하고 있어요",
                message: "알 수 없는 사유로 리포트를 표시할 수 없어요. 잠시 후 다시 확인해 주세요."
            )
        }
    }
}
