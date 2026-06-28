import SwiftUI

/// 설정 화면 — HomeView 상단 bell 버튼 → sheet.
/// REQ-05: '내 데이터 삭제' 진입점.
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AirPodsModel.storageKey) private var airPodsRawValue: String = AirPodsModel.default.rawValue

    @State private var showDeleteConfirmation = false
    @State private var showAirPodsPicker = false
    @State private var showChewDebug = false

    private var airPodsModel: AirPodsModel {
        AirPodsModel(rawValue: airPodsRawValue) ?? .default
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    deviceSection
                    sensitivitySection
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
        .sheet(isPresented: $showChewDebug) {
            ChewDebugView()
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

    /// 씹기 감지 디버그 진입. 진단 패널 + 개별 파라미터 슬라이더 + 게이트 우회 토글.
    private var sensitivitySection: some View {
        VStack(spacing: 0) {
            sectionHeader("씹기 감지 (디버그)")
            Button {
                showChewDebug = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.appFont(.medium, size: 18))
                        .foregroundStyle(Color.sage600)
                        .frame(width: 36, height: 36)
                        .background(Color.sage100, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("씹기 감지 튜닝 · 진단")
                            .font(.appFont(.semibold, size: 14))
                            .foregroundStyle(Color.ink600)
                        Text("파라미터 슬라이더 + 실시간 진단(왜 0인지)")
                            .font(.appFont(.medium, size: 12))
                            .foregroundStyle(Color.ink400)
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
            .accessibilityIdentifier("ChewDebugEntry")
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

            Button {
                Task {
                    await state.logoutFromServer()
                    dismiss()
                }
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.appFont(.medium, size: 16))
                        .foregroundStyle(Color.ink600)
                        .frame(width: 36, height: 36)
                        .background(Color.ink100, in: RoundedRectangle(cornerRadius: 10))

                    Text("로그아웃")
                        .font(.appFont(.medium, size: 16))
                        .foregroundStyle(Color.ink800)

                    Spacer()
                }
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                .neuoShadow(.sm)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .accessibilityIdentifier("Logout")
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

// MARK: - 씹기 감지 디버그 (진단 + 파라미터 튜닝)

/// 실기기에서 "왜 0인지"를 띄우고 파라미터를 즉석 조절하는 디버그 화면.
/// 측정 중 열어두면 폴링이 진단을 실시간 갱신한다.
private struct ChewDebugView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    diagnosticsCard
                    gateBypassCard
                    parametersCard
                    resetButton
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .background(Color.cream.ignoresSafeArea())
            .navigationTitle("씹기 감지 디버그")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                        .foregroundStyle(Color.acorn600)
                        .font(.appFont(.semibold, size: 15))
                }
            }
        }
    }

    // MARK: 진단 패널

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("실시간 진단")
                .font(.appFont(.bold, size: 14))
                .foregroundStyle(Color.ink800)

            if let d = state.liveChewDiagnostics, state.isEating {
                let s = state.chewSensitivity
                diagRow("샘플 수신", "\(d.sampleCount)", ok: d.sampleCount > 0)
                diagRow("봉우리 후보(게이트무시)", "\(d.rawPeakCount)", ok: d.rawPeakCount > 0)
                diagRow("실제 카운트", "\(d.chewCount)", ok: d.chewCount > 0)
                diagRow("씹는 중(게이트)", d.isChewing ? "O" : "X", ok: d.isChewing)

                Divider()
                diagRow("rotY std", fmt(d.rotationYStd, 3) + " ≥ " + fmt(s.minimumRotationYStd, 3),
                        ok: d.rotationYStd >= s.minimumRotationYStd)
                diagRow("rotY 우세도", fmt(d.rotationYDominance, 2) + " ≥ " + fmt(s.minimumRotationYDominance, 2),
                        ok: d.rotationYDominance >= s.minimumRotationYDominance)
                diagRow("jitter 우세도", fmt(d.rotationYJitterBandDominance, 2) + " ≥ " + fmt(s.minimumRotationYJitterBandDominance, 2),
                        ok: d.rotationYJitterBandDominance >= s.minimumRotationYJitterBandDominance)
                diagRow("accel/rotation", fmt(d.accelToRotation, 3) + " ≤ " + fmt(s.maximumAccelToRotation, 3),
                        ok: d.accelToRotation <= s.maximumAccelToRotation)
                diagRow("chewingLike(4조건 AND)", d.chewingLike ? "통과" : "막힘", ok: d.chewingLike)
                diagRow("hardJitter", d.hardJitterLike ? "차단됨" : "정상", ok: !d.hardJitterLike)

                Divider()
                diagRow("heading 차단 누적", "\(d.headingBlockedCount)", ok: true)
                diagRow("rotMag(현재)", fmt(d.lastRotMag, 3) + " ≤ " + fmt(s.headingMotionThreshold, 2),
                        ok: d.lastRotMag <= s.headingMotionThreshold)
            } else {
                Text("측정을 시작하면 진단이 실시간으로 떠요.\n설정을 연 채로 식사 시작 → 다시 이 화면을 열어 두세요.")
                    .font(.appFont(.medium, size: 12))
                    .foregroundStyle(Color.ink400)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }

    private func diagRow(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack {
            Text(label)
                .font(.appFont(.medium, size: 12))
                .foregroundStyle(Color.ink600)
            Spacer()
            Text(value)
                .font(.appFont(.semibold, size: 12))
                .foregroundStyle(ok ? Color.sage600 : Color.blush500)
                .monospacedDigit()
        }
    }

    private func fmt(_ v: Double, _ p: Int) -> String { String(format: "%.\(p)f", v) }

    // MARK: 게이트 우회

    private var gateBypassCard: some View {
        Toggle(isOn: bypassBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text("게이트 강제통과")
                    .font(.appFont(.semibold, size: 14))
                    .foregroundStyle(Color.ink800)
                Text("씹기 상태 게이트를 무시하고 봉우리만으로 카운트. 켰을 때 카운트가 터지면 게이트가 범인.")
                    .font(.appFont(.medium, size: 11))
                    .foregroundStyle(Color.ink400)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color.acorn500)
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }

    private var bypassBinding: Binding<Bool> {
        Binding(
            get: { state.chewSensitivity.bypassChewingGate },
            set: { var s = state.chewSensitivity; s.bypassChewingGate = $0; state.chewSensitivity = s }
        )
    }

    // MARK: 파라미터 슬라이더

    private var parametersCard: some View {
        let s = state.chewSensitivity
        return VStack(alignment: .leading, spacing: 14) {
            Text("파라미터")
                .font(.appFont(.bold, size: 14))
                .foregroundStyle(Color.ink800)

            sliderRow("진폭 하한 (낮을수록 민감)", value: fmt(s.minPeakAmplitude, 3),
                      binding: dbl(\.minPeakAmplitude), range: 0.002...0.020)
            sliderRow("피크 간격 (낮을수록 빠른 씹기)", value: "\(s.minPeakGap)",
                      binding: int(\.minPeakGap), range: 18...50)
            sliderRow("머리움직임 허용 (높을수록 관대)", value: fmt(s.headingMotionThreshold, 2),
                      binding: dbl(\.headingMotionThreshold), range: 0.04...0.40)

            Divider()
            sliderRow("저작 진폭 하한 (낮을수록 민감)", value: fmt(s.minimumRotationYStd, 3),
                      binding: dbl(\.minimumRotationYStd), range: 0.005...0.100)
            sliderRow("진입 지속 (낮을수록 빨리)", value: "\(s.enterSampleCount)",
                      binding: int(\.enterSampleCount), range: 2...30)
            sliderRow("종료 지속 (높을수록 안 끊김)", value: "\(s.exitSampleCount)",
                      binding: int(\.exitSampleCount), range: 20...150)

            Divider()
            Text("게이트(진동거부) — 0에 가까울수록 다 통과")
                .font(.appFont(.medium, size: 11))
                .foregroundStyle(Color.ink400)
            sliderRow("rotY 우세도 하한", value: fmt(s.minimumRotationYDominance, 2),
                      binding: dbl(\.minimumRotationYDominance), range: 0.0...0.6)
            sliderRow("jitter 우세도 하한", value: fmt(s.minimumRotationYJitterBandDominance, 2),
                      binding: dbl(\.minimumRotationYJitterBandDominance), range: 0.0...0.7)
            sliderRow("accel/rotation 상한 (높을수록 관대)", value: fmt(s.maximumAccelToRotation, 3),
                      binding: dbl(\.maximumAccelToRotation), range: 0.005...0.150)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }

    private func sliderRow(
        _ title: String,
        value: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.appFont(.medium, size: 12))
                    .foregroundStyle(Color.ink600)
                Spacer()
                Text(value)
                    .font(.appFont(.bold, size: 13))
                    .foregroundStyle(Color.acorn600)
                    .monospacedDigit()
            }
            Slider(value: binding, in: range)
                .tint(Color.acorn500)
        }
    }

    private func dbl(_ kp: WritableKeyPath<ChewSensitivity, Double>) -> Binding<Double> {
        Binding(
            get: { state.chewSensitivity[keyPath: kp] },
            set: { var s = state.chewSensitivity; s[keyPath: kp] = $0; state.chewSensitivity = s }
        )
    }

    private func int(_ kp: WritableKeyPath<ChewSensitivity, Int>) -> Binding<Double> {
        Binding(
            get: { Double(state.chewSensitivity[keyPath: kp]) },
            set: { var s = state.chewSensitivity; s[keyPath: kp] = Int($0.rounded()); state.chewSensitivity = s }
        )
    }

    private var resetButton: some View {
        Button {
            state.chewSensitivity = .defaults
        } label: {
            Text("기본값으로 초기화")
                .font(.appFont(.semibold, size: 15))
                .foregroundStyle(Color.blush500)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                .neuoShadow(.sm)
        }
        .buttonStyle(.plain)
    }
}
