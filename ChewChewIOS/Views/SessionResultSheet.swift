import SwiftUI

/// 식사 종료 직후 자동으로 표시되는 sheet — `ReportCardView`를 감싸고 닫기 CTA를 제공.
/// 공유/캘린더/다시 시작 CTA는 commit ②b 이후 단계에서 추가. 분석 5필드가 nil인
/// 세션(시뮬레이터/AirPods 미연결/60초 미만)은 PRD #3의 "분석을 만들지 못했어요" 빈 카드로
/// 대체.
struct SessionResultSheet: View {
    let dto: ChewingSessionDTO
    let onClose: () -> Void

    /// PNG 렌더는 ImageRenderer 호출 비용이 작지 않아 sheet 진입 시 1회만 만든다.
    /// 빈 상태(분석 5필드 nil) 세션에선 nil로 남아 공유 버튼이 자동 hidden.
    @State private var sharePayload: ReportCardSharePayload?

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let model = ReportCardModel.from(dto) {
                        ReportCardView(model: model)
                    } else {
                        EmptyReportCardView()
                    }
                }
                .padding(20)
            }
            .background(LinearGradient.appBackground.ignoresSafeArea())
            .navigationTitle("식사 리포트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let payload = sharePayload {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: payload, preview: SharePreview("식사 리포트")) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundStyle(Color.acorn600)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { onClose() }
                        .foregroundStyle(Color.ink600)
                }
            }
            .task {
                guard sharePayload == nil,
                      let model = ReportCardModel.from(dto),
                      let data = ReportCardRenderer.render(model)
                else { return }
                sharePayload = ReportCardSharePayload(imageData: data)
            }
        }
    }

}
