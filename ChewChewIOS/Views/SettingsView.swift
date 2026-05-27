import SwiftUI

/// 설정 화면 — HomeView 상단 bell 버튼 → sheet.
/// REQ-05: '내 데이터 삭제' 진입점.
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    deleteSection
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .background(LinearGradient.appBackground.ignoresSafeArea())
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                        .foregroundStyle(Color.acorn600)
                        .font(.appFont(.semibold, size: 15))
                }
            }
        }
        .confirmationDialog(
            "내 데이터를 삭제할까요?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("모두 삭제", role: .destructive) {
                Task { await state.eraseAllUserData() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("씹기 기록, 도토리, 스트릭 등 모든 데이터가 영구 삭제됩니다. 이 작업은 되돌릴 수 없습니다.")
        }
    }

    // MARK: - Subviews

    private var deleteSection: some View {
        VStack(spacing: 0) {
            sectionHeader("데이터")

            Button {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                        .font(.appFont(.medium, size: 16))
                        .foregroundStyle(Color.blush500)
                        .frame(width: 32, height: 32)
                        .background(Color.blush100, in: RoundedRectangle(cornerRadius: 10))

                    Text("내 데이터 삭제")
                        .font(.appFont(.medium, size: 16))
                        .foregroundStyle(Color.blush500)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.appFont(.medium, size: 13))
                        .foregroundStyle(Color.ink400)
                }
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                .neuoShadow(.sm)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("DeleteMyData")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.appFont(.semibold, size: 13))
                .foregroundStyle(Color.ink400)
            Spacer()
        }
        .padding(.bottom, 8)
    }
}
