import SwiftUI

struct ChewDebugView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    private var mealSession: MealSessionRuntimeStore { state.mealSession }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.gap) {
                    diagnosticsSection
                    gateBypassSection
                    parametersSection
                    resetButton
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.top, AppSpacing.gap)
                .padding(.bottom, AppSpacing.sectionGap)
            }
            .background(Color.pageBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    AppSheetTitleText(title: "씹기 감지 디버그")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AppSheetTextActionButton(title: "완료") { dismiss() }
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.three) {
            AppSettingsSectionHeader(title: "실시간 진단")

            VStack(spacing: AppSpacing.two) {
                if let diagnostics = mealSession.liveChewDiagnostics, mealSession.isEating {
                    let sensitivity = mealSession.chewSensitivity
                    diagnosticRow("샘플 수신", "\(diagnostics.sampleCount)", ok: diagnostics.sampleCount > 0)
                    diagnosticRow("봉우리 후보", "\(diagnostics.rawPeakCount)", ok: diagnostics.rawPeakCount > 0)
                    diagnosticRow("실제 카운트", "\(diagnostics.chewCount)", ok: diagnostics.chewCount > 0)
                    diagnosticRow("씹는 중", diagnostics.isChewing ? "통과" : "대기", ok: diagnostics.isChewing)
                    Divider()
                    diagnosticRow("rotY 표준편차", comparison(diagnostics.rotationYStd, sensitivity.minimumRotationYStd, digits: 3, symbol: ">="), ok: diagnostics.rotationYStd >= sensitivity.minimumRotationYStd)
                    diagnosticRow("rotY 우세도", comparison(diagnostics.rotationYDominance, sensitivity.minimumRotationYDominance, digits: 2, symbol: ">="), ok: diagnostics.rotationYDominance >= sensitivity.minimumRotationYDominance)
                    diagnosticRow("jitter 우세도", comparison(diagnostics.rotationYJitterBandDominance, sensitivity.minimumRotationYJitterBandDominance, digits: 2, symbol: ">="), ok: diagnostics.rotationYJitterBandDominance >= sensitivity.minimumRotationYJitterBandDominance)
                    diagnosticRow("accel / rotation", comparison(diagnostics.accelToRotation, sensitivity.maximumAccelToRotation, digits: 3, symbol: "<="), ok: diagnostics.accelToRotation <= sensitivity.maximumAccelToRotation)
                    diagnosticRow("chewingLike", diagnostics.chewingLike ? "통과" : "차단", ok: diagnostics.chewingLike)
                    diagnosticRow("hard jitter", diagnostics.hardJitterLike ? "차단" : "정상", ok: !diagnostics.hardJitterLike)
                    Divider()
                    diagnosticRow("heading 차단", "\(diagnostics.headingBlockedCount)", ok: true)
                    diagnosticRow("현재 rotMag", comparison(diagnostics.lastRotMag, sensitivity.headingMotionThreshold, digits: 3, symbol: "<="), ok: diagnostics.lastRotMag <= sensitivity.headingMotionThreshold)
                } else {
                    Text("측정을 시작하면 감지 상태가 실시간으로 표시돼요.")
                        .font(.appFont(.regularCallout))
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(AppSpacing.four)
            .background(Color.bgCard, in: RoundedRectangle(cornerRadius: AppRadius.container))
            .appElevation(.flat)
        }
    }

    private var gateBypassSection: some View {
        Toggle(isOn: boolBinding(\.bypassChewingGate)) {
            VStack(alignment: .leading, spacing: AppSpacing.one) {
                Text("게이트 강제통과")
                    .font(.appFont(.semiboldBody))
                    .foregroundStyle(Color.textPrimary)
                Text("씹기 상태 게이트를 무시하고 봉우리만 카운트해요.")
                    .font(.appFont(.regularCaption))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .tint(Color.dataChew)
        .padding(AppSpacing.four)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: AppRadius.container))
        .appElevation(.flat)
    }

    private var parametersSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.three) {
            AppSettingsSectionHeader(title: "파라미터")
            VStack(spacing: AppSpacing.four) {
                sliderRow("진폭 하한", value: formatted(mealSession.chewSensitivity.minPeakAmplitude, digits: 3), binding: doubleBinding(\.minPeakAmplitude), range: 0.002...0.020)
                sliderRow("피크 간격", value: "\(mealSession.chewSensitivity.minPeakGap) samples", binding: intBinding(\.minPeakGap), range: 8...50)
                sliderRow("머리 움직임 허용", value: formatted(mealSession.chewSensitivity.headingMotionThreshold, digits: 2), binding: doubleBinding(\.headingMotionThreshold), range: 0.04...0.40)
                Divider()
                sliderRow("저작 진폭 하한", value: formatted(mealSession.chewSensitivity.minimumRotationYStd, digits: 3), binding: doubleBinding(\.minimumRotationYStd), range: 0.005...0.100)
                sliderRow("진입 지속", value: "\(mealSession.chewSensitivity.enterSampleCount) samples", binding: intBinding(\.enterSampleCount), range: 2...30)
                sliderRow("종료 지속", value: "\(mealSession.chewSensitivity.exitSampleCount) samples", binding: intBinding(\.exitSampleCount), range: 2...150)
                Divider()
                sliderRow("rotY 우세도", value: formatted(mealSession.chewSensitivity.minimumRotationYDominance, digits: 2), binding: doubleBinding(\.minimumRotationYDominance), range: 0...0.6)
                sliderRow("jitter 우세도", value: formatted(mealSession.chewSensitivity.minimumRotationYJitterBandDominance, digits: 2), binding: doubleBinding(\.minimumRotationYJitterBandDominance), range: 0...0.7)
                sliderRow("accel / rotation 상한", value: formatted(mealSession.chewSensitivity.maximumAccelToRotation, digits: 3), binding: doubleBinding(\.maximumAccelToRotation), range: 0.005...0.150)
            }
            .padding(AppSpacing.four)
            .background(Color.bgCard, in: RoundedRectangle(cornerRadius: AppRadius.container))
            .appElevation(.flat)
        }
    }

    private func diagnosticRow(_ title: String, _ value: String, ok: Bool) -> some View {
        HStack(spacing: AppSpacing.two) {
            Text(title)
                .font(.appFont(.regularCallout))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.appFont(.semiboldCallout))
                .foregroundStyle(ok ? Color.dataChew : Color.statusDanger)
                .monospacedDigit()
        }
    }

    private func sliderRow(_ title: String, value: String, binding: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.two) {
            HStack {
                Text(title)
                    .font(.appFont(.regularCallout))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(value)
                    .font(.appFont(.semiboldCallout))
                    .foregroundStyle(Color.dataChew)
                    .monospacedDigit()
            }
            Slider(value: binding, in: range)
                .tint(Color.dataChew)
        }
    }

    private var resetButton: some View {
        Button("기본값으로 초기화") {
            mealSession.chewSensitivity = .defaults
        }
        .font(.appFont(.semiboldBody))
        .foregroundStyle(Color.statusDanger)
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.four)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: AppRadius.container))
        .buttonStyle(.plain)
        .accessibilityIdentifier("ChewDebugReset")
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<ChewSensitivity, Double>) -> Binding<Double> {
        Binding(
            get: { mealSession.chewSensitivity[keyPath: keyPath] },
            set: { value in
                var sensitivity = mealSession.chewSensitivity
                sensitivity[keyPath: keyPath] = value
                mealSession.chewSensitivity = sensitivity
            }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<ChewSensitivity, Int>) -> Binding<Double> {
        Binding(
            get: { Double(mealSession.chewSensitivity[keyPath: keyPath]) },
            set: { value in
                var sensitivity = mealSession.chewSensitivity
                sensitivity[keyPath: keyPath] = Int(value.rounded())
                mealSession.chewSensitivity = sensitivity
            }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<ChewSensitivity, Bool>) -> Binding<Bool> {
        Binding(
            get: { mealSession.chewSensitivity[keyPath: keyPath] },
            set: { value in
                var sensitivity = mealSession.chewSensitivity
                sensitivity[keyPath: keyPath] = value
                mealSession.chewSensitivity = sensitivity
            }
        )
    }

    private func formatted(_ value: Double, digits: Int) -> String {
        String(format: "%.*f", digits, value)
    }

    private func comparison(_ value: Double, _ threshold: Double, digits: Int, symbol: String) -> String {
        "\(formatted(value, digits: digits)) \(symbol) \(formatted(threshold, digits: digits))"
    }
}
