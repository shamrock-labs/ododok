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
            message: "씹기 기록, 도토리, 스트릭 모두 사라져요. 되돌릴 수 없어요.",
            primary: .init("모두 삭제", role: .destructive) {
                Task { await state.eraseAllUserData() }
            },
            secondary: .init("취소", role: .cancel) {}
        )
        .airPodsPickerDialog(
            isPresented: $showAirPodsPicker,
            selected: Binding(
                get: { airPodsModel },
                set: { airPodsRawValue = $0.rawValue }
            )
        )
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
                            .font(.appFont(.semibold, size: 14))
                            .foregroundStyle(Color.ink600)
                        Text(airPodsModel.displayName)
                            .font(.appFont(.bold, size: 15))
                            .foregroundStyle(Color.ink800)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.appFont(.semibold, size: 14))
                        .foregroundStyle(Color.ink600)
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
                        .font(.appFont(.semibold, size: 14))
                        .foregroundStyle(Color.ink600)
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
                .foregroundStyle(Color.ink600)
            Spacer()
        }
        .padding(.bottom, 8)
    }
}

// MARK: - AirPods Model Picker (dialog overlay)

/// 측정 기기 선택 다이얼로그. AppDialog와 동일한 시각 chrome(320pt, 22/28 padding,
/// 헤어라인 디바이더)에 라디오 리스트와 취소/확인 푸터를 얹은 형태.
private struct AirPodsPickerDialog: View {
    let initial: AirPodsModel
    let onConfirm: (AirPodsModel) -> Void
    let onCancel: () -> Void

    @State private var draft: AirPodsModel

    init(initial: AirPodsModel, onConfirm: @escaping (AirPodsModel) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _draft = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — title only, no body description.
            Text("사용 중인 AirPods 모델을 선택해요.")
                .font(.appFont(.heavy, size: 17))
                .foregroundStyle(Color.ink800)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)

            divider

            // Radio rows
            VStack(spacing: 0) {
                ForEach(Array(AirPodsModel.allCases.enumerated()), id: \.element.id) { idx, model in
                    row(model)
                    if idx < AirPodsModel.allCases.count - 1 {
                        divider.padding(.leading, 22)
                    }
                }
            }

            divider

            // Footer — 취소 / 확인
            HStack(spacing: 0) {
                Button {
                    onCancel()
                } label: {
                    Text("취소")
                        .font(.appFont(.semibold, size: 16))
                        .foregroundStyle(Color.ink600)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Color.ink100.frame(width: 0.5)

                Button {
                    onConfirm(draft)
                } label: {
                    Text("확인")
                        .font(.appFont(.bold, size: 16))
                        .foregroundStyle(Color.acorn700)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 44)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: 320)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
    }

    private var divider: some View {
        Color.ink100.frame(height: 0.5)
    }

    private func row(_ model: AirPodsModel) -> some View {
        let isActive = model == draft
        return Button {
            draft = model
        } label: {
            HStack(spacing: 14) {
                radio(isActive: isActive)
                Text(model.displayName)
                    .font(.appFont(.semibold, size: 15))
                    .foregroundStyle(Color.ink800)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// SF Symbol 없이 그린 라디오 버튼 — 외곽 원 + 활성 시 안쪽 닷.
    private func radio(isActive: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isActive ? Color.acorn600 : Color.ink400, lineWidth: 1.5)
                .frame(width: 20, height: 20)
            if isActive {
                Circle()
                    .fill(Color.acorn600)
                    .frame(width: 10, height: 10)
            }
        }
    }
}

private struct AirPodsPickerDialogOverlay: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selected: AirPodsModel

    func body(content: Content) -> some View {
        ZStack {
            content
            if isPresented {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { isPresented = false }
                AirPodsPickerDialog(
                    initial: selected,
                    onConfirm: { chosen in
                        selected = chosen
                        isPresented = false
                    },
                    onCancel: { isPresented = false }
                )
                .padding(.horizontal, 32)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isPresented)
    }
}

extension View {
    fileprivate func airPodsPickerDialog(
        isPresented: Binding<Bool>,
        selected: Binding<AirPodsModel>
    ) -> some View {
        modifier(AirPodsPickerDialogOverlay(isPresented: isPresented, selected: selected))
    }
}
