import SwiftUI

struct MeasurementOnboardingView: View {
    @Bindable var store: MeasurementOnboardingStore
    let onComplete: () -> Void
    let onSkip: () -> Void
    let onRetryConnection: () -> Void
    var skipTitle = "나중에"
    var isPreparingAirPods = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var diagnosticsShareItems: [URL] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            stepProgress

            ScrollView(showsIndicators: false) {
                VStack(spacing: accessibilityLayout ? AppSpacing.six : 0) {
                    stageContent

                    if accessibilityLayout {
                        actions
                            .padding(.horizontal, AppSpacing.page)
                    }
                }
                .padding(.bottom, accessibilityLayout ? AppSpacing.six : AppSpacing.four)
            }

            if !accessibilityLayout {
                actions
                    .padding(.horizontal, AppSpacing.page)
                    .padding(.top, AppSpacing.gap)
                    .padding(.bottom, AppSpacing.six)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.appBackground.ignoresSafeArea())
        .interactiveDismissDisabled(store.isMeasuring)
        .background {
            MeasurementDiagnosticsSharePresenter(items: $diagnosticsShareItems)
        }
    }

    private var accessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    private var stageContent: some View {
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
                Text(skipTitle)
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
            AirPodsConnectionReadinessVisual(
                isConnected: store.isAirPodsConnected,
                isPreparing: isPreparingAirPods
            )
        case .baseline:
            StillSignalMeasurementVisual(
                isMeasuring: store.isMeasuring,
                reduceMotion: reduceMotion
            )
        case .calibration:
            NaturalChewMeasurementVisual(
                isMeasuring: store.isMeasuring,
                isComplete: store.measurementCompleted,
                reduceMotion: reduceMotion
            )
        case .adjustment:
            MeasurementRhythmFeedbackVisual(
                cueIndex: store.cueIndex,
                cuePulseID: store.cuePulseID,
                cueHitID: store.cueHitID,
                approachDuration: store.adjustmentCueInterval,
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
                ("figure.stand", "5초 동안 편하게 멈춰 평소 움직임을 확인해요"),
                ("waveform", "평소처럼 10번 씹어 내 리듬을 찾아요"),
                ("checkmark.circle", "내 리듬으로 감지가 맞는지 확인해요"),
            ])
        case .connection:
            connectionStatus
        case .baseline, .calibration, .adjustment:
            measurementStatus
        case .ready:
            readyDetails
        case .signalIssue:
            if store.issue == .adjustmentNeeded {
                detailRows([
                    ("airpodspro", store.issue?.message ?? "AirPods 신호를 확인해 주세요"),
                    ("arrow.clockwise", "찾아둔 내 기준은 유지하고 리듬에 맞춰 한 번 더 씹어요"),
                ])
            } else {
                detailRows([
                    ("airpodspro", store.issue?.message ?? "AirPods 신호를 확인해 주세요"),
                    ("arrow.clockwise", "정지 상태 확인부터 다시 해볼게요"),
                ])
            }
        }
    }

    private var connectionStatus: some View {
        HStack(spacing: AppSpacing.gap) {
            if isPreparingAirPods {
                ProgressView()
                    .controlSize(.regular)
                    .frame(width: AppSize.iconXXLarge, height: AppSize.iconXXLarge)
            } else {
                Image(systemName: store.isAirPodsConnected ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.appFont(.regular, size: AppSize.iconXXLarge))
                    .foregroundStyle(store.isAirPodsConnected ? Color.statusSuccess : Color.statusWarning)
            }

            VStack(alignment: .leading, spacing: AppSpacing.microGap) {
                Text(connectionTitle)
                    .font(.appFont(.boldBody))
                    .foregroundStyle(Color.textDefault)
                Text(connectionMessage)
                    .font(.appFont(.regularCallout))
                    .foregroundStyle(Color.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.four)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: AppRadius.container))
    }

    private var connectionTitle: String {
        if isPreparingAirPods { return "AirPods를 준비하고 있어요" }
        return store.isAirPodsConnected ? "AirPods가 준비됐어요" : "AirPods에서 소리가 들리지 않았어요"
    }

    private var connectionMessage: String {
        if isPreparingAirPods { return "잠시 후 준비음이 들리는지 확인해 주세요." }
        return store.isAirPodsConnected
            ? "준비음이 들렸다면 다음으로 가요."
            : "AirPods를 착용한 뒤 다시 시도해 주세요."
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
        detailRows([
            ("waveform.path.ecg", "내 씹기 신호에 맞는 기준을 만들었어요"),
            ("metronome", "평소 씹는 리듬까지 확인했어요"),
            ("iphone", "맞춤 기준을 이 기기에 저장해요"),
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

            if store.stage == .connection && !store.isAirPodsConnected && !isPreparingAirPods {
                Button("다시 시도") {
                    onRetryConnection()
                }
                .buttonStyle(.plain)
                .font(.appFont(.boldLabel))
                .foregroundStyle(Color.textAction)
                .padding(.vertical, AppSpacing.two)
                .accessibilityIdentifier("MeasurementOnboardingRetryConnection")
            }

            if store.stage == .calibration && store.measurementCompleted {
                Button("다시 측정하기") {
                    Task { await store.retryMeasurement() }
                }
                .buttonStyle(.plain)
                .font(.appFont(.boldLabel))
                .foregroundStyle(Color.textAction)
                .padding(.vertical, AppSpacing.two)
                .accessibilityIdentifier("MeasurementOnboardingRetryCalibration")
            }

            if store.stage == .signalIssue, store.issue == .adjustmentNeeded {
                Button("측정부터 다시") {
                    Task { await store.retryMeasurement() }
                }
                .buttonStyle(.plain)
                .font(.appFont(.boldLabel))
                .foregroundStyle(Color.textAction)
                .padding(.vertical, AppSpacing.two)
                .accessibilityIdentifier("MeasurementOnboardingRestartCalibration")
            }

            if store.stage == .signalIssue, !store.diagnosticArtifactURLs.isEmpty {
                Button {
                    diagnosticsShareItems = store.diagnosticArtifactURLs
                } label: {
                    Label("측정 파일 공유", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .font(.appFont(.boldLabel))
                .foregroundStyle(Color.textAction)
                .padding(.vertical, AppSpacing.two)
                .accessibilityIdentifier("MeasurementOnboardingShareDiagnostics")
            }
        }
    }

    private var stageTitle: String {
        switch store.stage {
        case .intro: "내 리듬에 맞춰\n측정해볼까요?"
        case .connection: "먼저 AirPods를\n확인할게요"
        case .baseline: "5초 동안 편하게\n멈춰 있어 주세요"
        case .calibration: "평소처럼 자연스럽게\n10번 씹어보세요"
        case .adjustment: "이번에는 리듬에 맞춰\n씹어볼까요?"
        case .ready: "내 씹기 기준을\n확인했어요"
        case .signalIssue: "신호를 충분히\n읽지 못했어요"
        }
    }

    private var stageMessage: String {
        switch store.stage {
        case .intro: "사람마다 움직임과 씹는 속도가 달라요.\n식사 전에 짧게 나만의 기준을 맞춰요."
        case .connection: "연결된 AirPods의 움직임 센서를 확인해요."
        case .baseline: "가만히 있을 때 생기는 작은 움직임을 먼저 확인해요.\n고개와 턱에 힘을 빼고 편하게 있어 주세요."
        case .calibration: "속도에 신경 쓰지 말고 평소 식사하듯 씹어주세요.\n10번을 다 씹으면 측정 완료를 눌러요."
        case .adjustment: "오른쪽에서 오는 신호가 왼쪽에 닿을 때 편안하게 씹어주세요.\n감지 횟수는 화면에 표시하지 않아요."
        case .ready: "다음 식사부터 이 기준으로 씹기를 감지해요."
        case .signalIssue: "괜찮아요. 착용 상태와 씹는 리듬을 확인해요."
        }
    }

    private var measurementStatusText: String {
        if store.measurementCompleted {
            return "내 씹기 크기와 리듬을 찾았어요"
        }
        if store.isMeasuring {
            if store.stage == .baseline {
                return "평소 움직임을 확인하고 있어요"
            }
            if store.stage == .calibration {
                return store.isFinishingMeasurement
                    ? "측정한 신호를 정리하고 있어요"
                    : "10번을 다 씹은 뒤 측정 완료를 눌러주세요"
            }
            return "내 리듬으로 감지를 확인하고 있어요"
        }
        switch store.stage {
        case .baseline:
            return "준비되면 5초 동안 편하게 멈춰 있어요"
        case .calibration:
            return "준비되면 자연스러운 씹기를 측정해요"
        default:
            return "준비되면 내 리듬으로 확인해요"
        }
    }

    private var primaryTitle: String {
        switch store.stage {
        case .intro: return "맞춤 측정 준비하기"
        case .connection: return "다음"
        case .baseline: return store.isMeasuring ? "정지 신호 확인 중" : "5초 측정 시작"
        case .calibration:
            if store.isFinishingMeasurement { return "신호 확인 중" }
            if store.isMeasuring { return "측정 완료" }
            return store.measurementCompleted ? "리듬에 맞춰 씹기" : "측정 시작하기"
        case .adjustment: return store.isMeasuring ? "내 리듬 확인 중" : "리듬에 맞춰 씹기"
        case .ready: return "맞춤 기준 사용하기"
        case .signalIssue: return store.issue == .adjustmentNeeded ? "한 번 더 해보기" : "측정 다시하기"
        }
    }

    private var primaryIcon: String? {
        switch store.stage {
        case .intro: "waveform.path.ecg"
        case .connection: "arrow.right"
        case .baseline: "record.circle"
        case .calibration:
            store.isMeasuring ? "stop.circle" : store.measurementCompleted ? "arrow.right" : "record.circle"
        case .adjustment: "record.circle"
        case .ready: "checkmark"
        case .signalIssue: "arrow.clockwise"
        }
    }

    private var primaryDisabled: Bool {
        store.isFinishingMeasurement || store.isRestartingMeasurement
            || (store.stage == .baseline && store.isMeasuring)
            || (store.stage == .adjustment && store.isMeasuring) || (store.stage == .connection
                && (!store.isAirPodsConnected || isPreparingAirPods))
    }

    private func handlePrimaryAction() {
        switch store.stage {
        case .baseline where !store.isMeasuring:
            store.startMeasurement()
        case .calibration where store.isMeasuring:
            Task { await store.finishNaturalMeasurement() }
        case .calibration where !store.measurementCompleted,
             .adjustment where !store.measurementCompleted:
            store.startMeasurement()
        case .ready:
            onComplete()
        case .signalIssue:
            if store.issue == .adjustmentNeeded {
                Task { await store.retryAdjustment() }
            } else {
                Task { await store.retryMeasurement() }
            }
        default:
            withAnimation(.easeInOut(duration: AppMotion.durationPageChange)) {
                store.moveForward()
            }
        }
    }
}

private struct StillSignalMeasurementVisual: View {
    let isMeasuring: Bool
    let reduceMotion: Bool

    @State private var breathing = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Color.tintInteractive.opacity(0.14), lineWidth: AppSize.border)
                    .frame(width: 108 + CGFloat(index * 22))
                    .scaleEffect(breathing && isMeasuring && !reduceMotion ? 1.02 : 0.98)
                    .opacity(isMeasuring ? 0.8 - Double(index) * 0.18 : 0.42)
                    .animation(
                        .easeInOut(duration: AppMotion.durationWave)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: breathing
                    )
            }

            Circle()
                .fill(Color.bgSurface)
                .frame(width: Metrics.signalCore, height: Metrics.signalCore)

            Image(systemName: "figure.stand")
                .font(.appFont(.regular, size: Metrics.heroIcon))
                .foregroundStyle(Color.textActionStrong)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("정지 상태 측정")
        .accessibilityValue(isMeasuring ? "측정 중" : "측정 전")
        .onAppear { breathing = true }
    }
}

private struct NaturalChewMeasurementVisual: View {
    let isMeasuring: Bool
    let isComplete: Bool
    let reduceMotion: Bool

    @State private var breathing = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(ringColor.opacity(0.16), lineWidth: AppSize.border)
                    .frame(width: 112 + CGFloat(index * 22))
                    .scaleEffect(breathing && !reduceMotion ? 1.04 + Double(index) * 0.025 : 0.96)
                    .opacity(breathing && !reduceMotion ? 0.4 : 0.9 - Double(index) * 0.18)
                    .animation(
                        .easeInOut(duration: AppMotion.durationWave)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.14),
                        value: breathing
                    )
            }

            SquirrelView(
                mood: .happy,
                hat: nil,
                glasses: nil,
                acc: nil,
                animKey: isMeasuring ? 1 : 0,
                isEating: isMeasuring
            )
            .scaleEffect(0.9)

            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.appFont(.regular, size: AppSize.iconXXLarge))
                    .foregroundStyle(Color.statusSuccess)
                    .offset(x: 58, y: -50)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("자연스러운 씹기 측정")
        .accessibilityValue(accessibilityValue)
        .onAppear { breathing = true }
    }

    private var ringColor: Color {
        isComplete ? .statusSuccess : .tintInteractive
    }

    private var accessibilityValue: String {
        if isComplete { return "측정 완료" }
        if isMeasuring { return "측정 중" }
        return "측정 전"
    }
}

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
    static let progressHeight: CGFloat = 5
}
