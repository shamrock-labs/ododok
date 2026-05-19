import SwiftUI

/// 식사 종료 직후 자동으로 표시되는 sheet — `ReportCardView`를 감싸고 닫기 CTA를 제공.
/// 공유/캘린더/다시 시작 CTA는 commit ②b 이후 단계에서 추가. 분석 5필드가 nil인
/// 세션(시뮬레이터/AirPods 미연결/60초 미만)은 PRD #3의 "데이터가 부족해요" 빈 카드로
/// 대체.
struct SessionResultSheet: View {
    let dto: ChewingSessionDTO
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let model = ReportCardModel.from(dto) {
                        ReportCardView(model: model)
                    } else {
                        emptyCard
                    }
                }
                .padding(20)
            }
            .background(LinearGradient.appBackground.ignoresSafeArea())
            .navigationTitle("식사 리포트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { onClose() }
                        .foregroundStyle(Color.ink600)
                }
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 14) {
            Text("🐿️").font(.system(size: 48))
            Text("데이터가 부족해요")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color.ink800)
            Text("식사 시간이 너무 짧거나, AirPods IMU 신호를 받지 못해\n이번 식사의 분석을 만들지 못했어요.")
                .font(.system(size: 13))
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
