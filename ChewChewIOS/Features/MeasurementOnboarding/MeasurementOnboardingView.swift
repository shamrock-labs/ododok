import SwiftUI

struct MeasurementOnboardingView: View {
    @Bindable var store: MeasurementOnboardingStore
    let onComplete: () -> Void
    let onSkip: () -> Void
    let onRetryConnection: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            stepProgress

            ScrollView(showsIndicators: false) {
                VStack(spacing: AppSpacing.six) {
                    stageVisual
                        .frame(height: Metrics.visualHeight)

                    VStack(spacing: AppSpacing.gap) {
                        Text(stageTitle)
                            .font(.appFont(.heavyDisplay))
                            .foregroundStyle(Color.textDefault)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(stageMessage)
                            .font(.appFont(.regularBodyLarge))
                            .foregroundStyle(Color.textMuted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    stageDetail
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.top, AppSpacing.seven)
                .padding(.bottom, AppSpacing.four)
            }

            actions
                .padding(.horizontal, AppSpacing.page)
                .padding(.top, AppSpacing.gap)
                .padding(.bottom, AppSpacing.six)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.appBackground.ignoresSafeArea())
        .interactiveDismissDisabled(store.isMeasuring)
        .onDisappear { store.cancelMeasurement() }
    }

    private var header: some View {
        HStack {
            AppBadge(
                text: "맞춤 측정 준비",
                foreground: .textAction,
                background: .bgSelected
            )

            Spacer()

            Button(action: onSkip) {
                Text("나중에")
                    .font(.appFont(.boldLabel))
                    .foregroundStyle(Color.textMuted)
                    .frame(minWidth: AppSize.dialogActionHeight, minHeight: AppSize.dialogActionHeight)
            }
            .buttonStyle(.plain)
            .disabled(store.isMeasuring)
            .accessibilityIdentifier("MeasurementOnboardingSkip")
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, AppSpacing.four)
    }

    private var stepProgress: some View {
        HStack(spacing: AppSpacing.two) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index <= store.stage.progressIndex ? Color.tintInteractive : Color.borderDefault)
                    .frame(height: Metrics.progressHeight)
            }
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, AppSpacing.gap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("맞춤 측정 준비 \(min(store.stage.progressIndex + 1, 4))단계")
    }

    @ViewBuilder
    private var stageVisual: some View {
        switch store.stage {
        case .intro:
            IntroSignalVisual(reduceMotion: reduceMotion)
        case .connection:
            ConnectionVisual(isConnected: store.isAirPodsConnected)
        case .calibration:
            SignalCaptureVisual(
                mode: .calibration,
                cueIndex: store.cueIndex,
                cueCount: store.cueCount,
                detectedCount: store.calibrationAmplitudes.count,
                cuePulseID: store.cuePulseID,
                reduceMotion: reduceMotion
            )
        case .validation:
            SignalCaptureVisual(
                mode: .validation,
                cueIndex: store.cueIndex,
                cueCount: store.cueCount,
                detectedCount: store.validationDetectedCount,
                cuePulseID: store.cuePulseID,
                reduceMotion: reduceMotion
            )
        case .ready:
            ReadyVisual()
        case .signalIssue:
            SignalIssueVisual()
        }
    }

    @ViewBuilder
    private var stageDetail: some View {
        switch store.stage {
        case .intro:
            detailRows([
                ("airpodspro", "AirPods 연결을 확인해요"),
                ("metronome", "박자에 맞춰 10번 씹어 기준을 맞춰요"),
                ("checkmark.circle", "다시 10번 씹어 감지가 맞는지 확인해요"),
            ])
        case .connection:
            connectionStatus
        case .calibration, .validation:
            measurementStatus
        case .ready:
            readyDetails
        case .signalIssue:
            detailRows([
                ("airpodspro", store.issue?.message ?? "AirPods 신호를 확인해 주세요"),
                ("arrow.clockwise", "처음 10회 보정부터 다시 해볼게요"),
            ])
        }
    }

    private var connectionStatus: some View {
        HStack(spacing: AppSpacing.gap) {
            Image(systemName: store.isAirPodsConnected ? "checkmark.circle.fill" : "circle.dashed")
                .font(.appFont(.regular, size: AppSize.iconXXLarge))
                .foregroundStyle(store.isAirPodsConnected ? Color.statusSuccess : Color.textSubtle)

            VStack(alignment: .leading, spacing: AppSpacing.microGap) {
                Text(store.isAirPodsConnected ? "AirPods가 연결됐어요" : "AirPods 연결을 기다리고 있어요")
                    .font(.appFont(.boldBody))
                    .foregroundStyle(Color.textDefault)
                Text(store.isAirPodsConnected ? "양쪽을 착용했다면 다음으로 가요." : "연결하고 양쪽을 착용해 주세요.")
                    .font(.appFont(.regularCallout))
                    .foregroundStyle(Color.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.four)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: AppRadius.container))
    }

    private var measurementStatus: some View {
        HStack(spacing: AppSpacing.gap) {
            Image(systemName: store.measurementCompleted ? "checkmark.circle.fill" : "waveform")
                .font(.appFont(.regular, size: AppSize.iconXXLarge))
                .foregroundStyle(store.measurementCompleted ? Color.statusSuccess : Color.textAction)

            Text(measurementStatusText)
                .font(.appFont(.semiboldBody))
                .foregroundStyle(Color.textDefault)
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.four)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: AppRadius.container))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("측정 상태")
        .accessibilityValue(measurementStatusText)
    }

    private var readyDetails: some View {
        let threshold = store.profile?.minPeakAmplitude ?? 0
        let detectedCount = store.profile?.validationDetectedCount ?? 0
        return detailRows([
            ("slider.horizontal.3", String(format: "개인 진폭 기준 %.4f", threshold)),
            ("checkmark.circle", "검증 10회 중 \(detectedCount)회 감지했어요"),
            ("iphone", "결과는 이 기기에서만 확인해요"),
        ])
    }

    private func detailRows(_ rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: AppSpacing.gap) {
                    Image(systemName: row.0)
                        .font(.appFont(.mediumHeadline))
                        .foregroundStyle(Color.textAction)
                        .frame(width: AppSize.iconXXLarge)
                    Text(row.1)
                        .font(.appFont(.semiboldBody))
                        .foregroundStyle(Color.textDefault)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, AppSpacing.four)

                if index < rows.count - 1 {
                    Divider().foregroundStyle(Color.borderDefault)
                }
            }
        }
        .padding(.horizontal, AppSpacing.four)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: AppRadius.container))
    }

    private var actions: some View {
        VStack(spacing: AppSpacing.gapTight) {
            AppTextActionButton(
                title: primaryTitle,
                icon: primaryIcon,
                font: .boldBodyLarge
            ) {
                handlePrimaryAction()
            }
            .opacity(primaryDisabled ? 0.48 : 1)
            .allowsHitTesting(!primaryDisabled)
            .accessibilityIdentifier("MeasurementOnboardingPrimary")

            if store.stage == .connection && !store.isAirPodsConnected {
                Button("연결 상태 다시 확인") {
                    onRetryConnection()
                }
                .buttonStyle(.plain)
                .font(.appFont(.boldLabel))
                .foregroundStyle(Color.textAction)
                .padding(.vertical, AppSpacing.two)
                .accessibilityIdentifier("MeasurementOnboardingRetryConnection")
            }
        }
    }

    private var stageTitle: String {
        switch store.stage {
        case .intro: "내 리듬에 맞춰\n측정해볼까요?"
        case .connection: "먼저 AirPods를\n확인할게요"
        case .calibration: "박자에 맞춰\n10번 씹어볼까요?"
        case .validation: "같은 리듬으로\n10번 더 확인할게요"
        case .ready: "내 씹기 기준을\n확인했어요"
        case .signalIssue: "신호를 충분히\n읽지 못했어요"
        }
    }

    private var stageMessage: String {
        switch store.stage {
        case .intro: "사람마다 움직임과 씹는 속도가 달라요.\n식사 전에 짧게 나만의 기준을 맞춰요."
        case .connection: "연결된 AirPods의 움직임 센서를 확인해요."
        case .calibration: "화면의 박자가 움직일 때 한 번씩 씹어주세요.\n10회의 신호로 내 기준을 계산해요."
        case .validation: "방금 만든 기준으로 실제 감지 횟수를 확인해요."
        case .ready: "서버에 저장하지 않은 로컬 실험 결과예요."
        case .signalIssue: "괜찮아요. 착용 상태와 씹는 리듬을 확인해요."
        }
    }

    private var measurementStatusText: String {
        if store.measurementCompleted {
            return "10회의 신호로 개인 기준을 만들었어요"
        }
        if store.isMeasuring {
            if store.stage == .calibration {
                return "기준 신호 \(store.calibrationAmplitudes.count)/10개 확보"
            }
            return "DSP가 \(store.validationDetectedCount)회 감지했어요"
        }
        return store.stage == .calibration
            ? "준비되면 10회 보정을 시작해요"
            : "준비되면 새 기준으로 10회를 확인해요"
    }

    private var primaryTitle: String {
        switch store.stage {
        case .intro:
            return "맞춤 측정 준비하기"
        case .connection:
            return "다음"
        case .calibration:
            if store.isMeasuring { return "보정 중 · \(store.cueIndex)/10" }
            return store.measurementCompleted ? "검증 10회로 이동" : "10회 보정 시작"
        case .validation:
            if store.isMeasuring { return "검증 중 · \(store.cueIndex)/10" }
            return "10회 검증 시작"
        case .ready:
            return "결과 확인"
        case .signalIssue:
            return "처음부터 다시"
        }
    }

    private var primaryIcon: String? {
        switch store.stage {
        case .intro: "waveform.path.ecg"
        case .connection: "arrow.right"
        case .calibration, .validation: store.measurementCompleted ? "arrow.right" : "record.circle"
        case .ready: "checkmark"
        case .signalIssue: "arrow.clockwise"
        }
    }

    private var primaryDisabled: Bool {
        store.isMeasuring || (store.stage == .connection && !store.isAirPodsConnected)
    }

    private func handlePrimaryAction() {
        switch store.stage {
        case .calibration, .validation where !store.measurementCompleted:
            store.startMeasurement()
        case .ready:
            onComplete()
        case .signalIssue:
            store.retryMeasurement()
        default:
            withAnimation(.easeInOut(duration: AppMotion.durationPageChange)) {
                store.moveForward()
            }
        }
    }
}

#if DEBUG
struct MeasurementOnboardingPreviewHost: View {
    @State private var store: MeasurementOnboardingStore

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let stage: MeasurementOnboardingStore.Stage
        if let index = arguments.firstIndex(of: "-measurementOnboardingStage"),
           index + 1 < arguments.count,
           let requestedStage = MeasurementOnboardingStore.Stage(rawValue: arguments[index + 1]) {
            stage = requestedStage
        } else {
            stage = .intro
        }
        #if targetEnvironment(simulator)
        let sampler: any MeasurementCalibrationSampling = SimulatedMeasurementCalibrationSampler()
        #else
        let sampler: any MeasurementCalibrationSampling = LocalMeasurementCalibrationSampler()
        #endif
        _store = State(initialValue: MeasurementOnboardingStore.preview(
            stage: stage,
            sampler: sampler
        ))
    }

    var body: some View {
        MeasurementOnboardingView(
            store: store,
            onComplete: {},
            onSkip: {},
            onRetryConnection: { store.setAirPodsConnected(true) }
        )
        .task {
            if store.stage == .calibration || store.stage == .validation {
                store.startMeasurement()
            }
        }
    }
}
#endif

private struct IntroSignalVisual: View {
    let reduceMotion: Bool
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Color.tintInteractive.opacity(0.24), lineWidth: AppSize.border)
                    .frame(width: Metrics.signalRing, height: Metrics.signalRing)
                    .scaleEffect(animate && !reduceMotion ? 1.18 + Double(index) * 0.13 : 0.78 + Double(index) * 0.12)
                    .opacity(animate && !reduceMotion ? 0.18 : 0.7)
                    .animation(
                        .easeInOut(duration: AppMotion.durationWave)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.18),
                        value: animate
                    )
            }

            Circle()
                .fill(Color.bgSurface)
                .frame(width: Metrics.signalCore, height: Metrics.signalCore)

            Image(systemName: "waveform.path.ecg")
                .font(.appFont(.regular, size: Metrics.heroIcon))
                .foregroundStyle(Color.textActionStrong)
        }
        .onAppear { animate = true }
    }
}

private struct ConnectionVisual: View {
    let isConnected: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.bgSurface)
                .frame(width: Metrics.signalCore, height: Metrics.signalCore)
                .overlay {
                    Image(systemName: "airpodspro")
                        .font(.appFont(.regular, size: Metrics.heroIcon))
                        .foregroundStyle(Color.textActionStrong)
                }

            Image(systemName: isConnected ? "checkmark.circle.fill" : "ellipsis.circle.fill")
                .font(.appFont(.regular, size: Metrics.statusIcon))
                .foregroundStyle(isConnected ? Color.statusSuccess : Color.statusWarning)
                .background(Color.bgPage, in: Circle())
        }
    }
}

private enum SignalCaptureMode {
    case calibration
    case validation

    var tint: Color {
        switch self {
        case .calibration: .tintInteractive
        case .validation: .dataTime
        }
    }

    var label: String {
        switch self {
        case .calibration: "기준"
        case .validation: "감지"
        }
    }
}

private struct SignalCaptureVisual: View {
    let mode: SignalCaptureMode
    let cueIndex: Int
    let cueCount: Int
    let detectedCount: Int
    let cuePulseID: Int
    let reduceMotion: Bool

    @State private var isScanning = false
    @State private var cueFlash = false

    private let markCount = 24

    var body: some View {
        ZStack {
            Circle()
                .fill(mode.tint.opacity(cueFlash ? 0.15 : 0.055))
                .frame(width: Metrics.signalHalo, height: Metrics.signalHalo)
                .scaleEffect(isScanning && !reduceMotion ? 1.05 : 0.95)

            Circle()
                .stroke(mode.tint.opacity(0.10), lineWidth: AppSize.border)
                .frame(width: Metrics.signalOrbit, height: Metrics.signalOrbit)

            ForEach(0..<markCount, id: \.self) { index in
                Capsule()
                    .fill(mode.tint.opacity(markOpacity(at: index)))
                    .frame(width: Metrics.signalMarkWidth, height: Metrics.signalMarkHeight)
                    .offset(y: -Metrics.signalMarkRadius)
                    .rotationEffect(.degrees(Double(index) * (360 / Double(markCount))))
                    .scaleEffect(markScale(at: index))
                    .animation(
                        .easeOut(duration: AppMotion.durationStateChange),
                        value: detectedCount
                    )
            }

            Circle()
                .trim(from: 0.04, to: 0.18)
                .stroke(
                    mode.tint.opacity(reduceMotion ? 0 : 0.55),
                    style: StrokeStyle(lineWidth: Metrics.scanLineWidth, lineCap: .round)
                )
                .frame(width: Metrics.signalOrbit, height: Metrics.signalOrbit)
                .rotationEffect(.degrees(isScanning ? 360 : 0))
                .animation(
                    reduceMotion
                        ? nil
                        : .linear(duration: AppMotion.durationWave).repeatForever(autoreverses: false),
                    value: isScanning
                )

            Circle()
                .fill(Color.bgSurface.opacity(0.84))
                .frame(width: Metrics.signalCoreCompact, height: Metrics.signalCoreCompact)
                .overlay {
                    Circle()
                        .stroke(Color.bgSurface.opacity(0.94), lineWidth: Metrics.coreBorderWidth)
                }

            VStack(spacing: AppSpacing.half) {
                Image(systemName: mode == .calibration ? "waveform.path" : "waveform.path.ecg")
                    .font(.appFont(.regular, size: Metrics.signalGlyph))
                    .foregroundStyle(mode.tint.opacity(0.88))
                    .scaleEffect(cueFlash && !reduceMotion ? 1.12 : 1)

                Text("\(detectedCount)")
                    .font(.appFont(.heavyTitleLarge))
                    .foregroundStyle(Color.textDefault)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(mode.label)
                    .font(.appFont(.boldCaption))
                    .foregroundStyle(Color.textMuted)
            }

            Text("\(cueIndex) / \(cueCount)")
                .font(.appFont(.boldCaption))
                .foregroundStyle(mode.tint)
                .monospacedDigit()
                .padding(.horizontal, AppSpacing.inner)
                .padding(.vertical, AppSpacing.oneHalf)
                .background(Color.bgSurface.opacity(0.92), in: Capsule())
                .overlay {
                    Capsule().stroke(mode.tint.opacity(0.12), lineWidth: AppSize.border)
                }
                .offset(y: Metrics.counterOffset)
        }
        .frame(width: Metrics.signalFrame, height: Metrics.signalFrame)
        .animation(.easeOut(duration: AppMotion.durationStateChange), value: detectedCount)
        .onAppear { isScanning = true }
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(duration: AppMotion.durationWave).repeatForever(autoreverses: true),
            value: isScanning
        )
        .onChange(of: cuePulseID) { _, _ in
            cueFlash = true
            Task {
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.easeOut(duration: AppMotion.durationStateChange)) {
                    cueFlash = false
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mode.label) 측정")
        .accessibilityValue("안내 \(cueIndex)회 중 신호 \(detectedCount)회")
    }

    private func markOpacity(at index: Int) -> Double {
        let completedMarks = Int((Double(markCount) * signalProgress).rounded(.down))
        if index < completedMarks { return 0.82 }
        return index.isMultiple(of: 3) ? 0.22 : 0.10
    }

    private func markScale(at index: Int) -> CGFloat {
        let completedMarks = Int((Double(markCount) * signalProgress).rounded(.down))
        return index < completedMarks ? 1 : 0.72
    }

    private var signalProgress: Double {
        min(Double(detectedCount) / Double(cueCount), 1)
    }
}

private struct ReadyVisual: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Color.statusSuccess.opacity(0.12), lineWidth: AppSize.border)
                    .frame(width: Metrics.signalCore + CGFloat(index * 18))
                    .scaleEffect(appeared ? 1 : 0.82)
                    .opacity(appeared ? 1 - Double(index) * 0.22 : 0)
                    .animation(
                        .easeOut(duration: AppMotion.durationProgress)
                            .delay(Double(index) * 0.08),
                        value: appeared
                    )
            }

            Circle()
                .fill(Color.statusSuccessMuted.opacity(0.78))
                .frame(width: Metrics.signalCore, height: Metrics.signalCore)
            Image(systemName: "checkmark")
                .font(.appFont(.heavy, size: Metrics.heroIcon))
                .foregroundStyle(Color.statusSuccess)
                .scaleEffect(appeared ? 1 : 0.62)
                .opacity(appeared ? 1 : 0)
                .animation(
                    .spring(
                        response: AppMotion.springResponse,
                        dampingFraction: AppMotion.springDampingFraction
                    ),
                    value: appeared
                )
        }
        .onAppear { appeared = true }
    }
}

private struct SignalIssueVisual: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.statusWarningMuted)
                .frame(width: Metrics.signalCore, height: Metrics.signalCore)
            Image(systemName: "waveform.slash")
                .font(.appFont(.regular, size: Metrics.heroIcon))
                .foregroundStyle(Color.statusWarning)
        }
    }
}

private enum Metrics {
    static let visualHeight: CGFloat = 180
    static let signalRing: CGFloat = 150
    static let signalCore: CGFloat = 132
    static let heroIcon: CGFloat = 54
    static let statusIcon: CGFloat = 34
    static let signalFrame: CGFloat = 172
    static let signalHalo: CGFloat = 164
    static let signalOrbit: CGFloat = 148
    static let signalCoreCompact: CGFloat = 104
    static let signalMarkWidth: CGFloat = 4
    static let signalMarkHeight: CGFloat = 11
    static let signalMarkRadius: CGFloat = 74
    static let signalGlyph: CGFloat = 24
    static let scanLineWidth: CGFloat = 5
    static let coreBorderWidth: CGFloat = 8
    static let counterOffset: CGFloat = 100
    static let progressHeight: CGFloat = 5
}
