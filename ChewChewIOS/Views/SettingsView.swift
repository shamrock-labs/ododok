import SwiftUI

/// 설정 화면 — HomeView 상단 bell 버튼 → sheet.
/// REQ-05: '내 데이터 삭제' 진입점.
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AirPodsModel.storageKey) private var airPodsRawValue: String = AirPodsModel.default.rawValue

    @State private var showDeleteConfirmation = false
    @State private var showAirPodsPicker = false

    private var airPodsModel: AirPodsModel {
        AirPodsModel(rawValue: airPodsRawValue) ?? .default
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    deviceSection
                    deleteSection
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .background(Color.cream.ignoresSafeArea())
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
        .appDialog(
            isPresented: $showDeleteConfirmation,
            title: "내 데이터를 삭제할까요?",
            message: "씹기 기록, 도토리, 스트릭 등 모든 데이터가 영구 삭제됩니다. 이 작업은 되돌릴 수 없습니다.",
            primary: .init("모두 삭제", role: .destructive) {
                Task { await state.eraseAllUserData() }
            },
            secondary: .init("취소", role: .cancel) {}
        )
        .sheet(isPresented: $showAirPodsPicker) {
            AirPodsModelPicker(selected: Binding(
                get: { airPodsModel },
                set: { airPodsRawValue = $0.rawValue }
            ))
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sections

    private var deviceSection: some View {
        VStack(spacing: 0) {
            sectionHeader("기기")

            Button {
                showAirPodsPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "airpodspro")
                        .font(.appFont(.medium, size: 18))
                        .foregroundStyle(Color.sage600)
                        .frame(width: 36, height: 36)
                        .background(Color.sage100, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("측정 기기")
                            .font(.appFont(.medium, size: 13))
                            .foregroundStyle(Color.ink400)
                        Text(airPodsModel.displayName)
                            .font(.appFont(.bold, size: 15))
                            .foregroundStyle(Color.ink800)
                    }

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
            .accessibilityIdentifier("AirPodsModelPicker")
        }
    }

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
                        .frame(width: 36, height: 36)
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

// MARK: - AirPods Model Picker (bottom sheet)

/// 사용자가 자신의 AirPods 모델을 선택하는 바텀 시트 picker.
/// daramg-demo의 모델 선택 UI 패턴(흰 카드 행 + 체크 마커)을 iOS에 옮긴 것.
private struct AirPodsModelPicker: View {
    @Binding var selected: AirPodsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("측정 기기 선택")
                    .font(.appFont(.heavy, size: 17))
                    .foregroundStyle(Color.ink800)
                Text("사용 중인 AirPods 모델을 선택해 주세요")
                    .font(.appFont(.medium, size: 12))
                    .foregroundStyle(Color.ink400)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(AirPodsModel.allCases) { model in
                        row(model)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cream.ignoresSafeArea())
    }

    private func row(_ model: AirPodsModel) -> some View {
        let isActive = model == selected
        return Button {
            selected = model
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "airpodspro")
                    .font(.appFont(.medium, size: 16))
                    .foregroundStyle(Color.sage600)
                    .frame(width: 36, height: 36)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .neuoShadow(.sm)

                Text(model.displayName)
                    .font(.appFont(.bold, size: 15))
                    .foregroundStyle(Color.ink800)

                Spacer(minLength: 0)

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.appFont(.bold, size: 14))
                        .foregroundStyle(Color.sage600)
                }
            }
            .padding(14)
            .background(
                isActive ? Color.sage50 : Color.white,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isActive ? Color.sage400 : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
