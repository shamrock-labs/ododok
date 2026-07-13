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
        case .rest:
            MeasurementProgressVisual(
                progress: store.progress,
                remainingSeconds: store.remainingSeconds,
                symbol: "figure.mind.and.body",
                tint: .dataTime
            )
        case .chew:
            ChewRhythmVisual(progress: store.progress, reduceMotion: reduceMotion)
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
                ("figure.stand", "10초 동안 편한 자세를 읽어요"),
                ("waveform.path", "평소 씹기 리듬을 확인해요"),
            ])
        case .connection:
            connectionStatus
        case .rest, .chew:
            measurementStatus
        case .ready:
            detailRows([
                ("checkmark.circle", "내 움직임의 기준을 준비했어요"),
                ("fork.knife", "이제 평소처럼 식사하면 돼요"),
            ])
        case .signalIssue:
            detailRows([
                ("airpodspro", "AirPods를 귀에 착용해 주세요"),
                ("arrow.clockwise", "같은 자세에서 한 번 더 해볼게요"),
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
        case .rest: "10초만 편하게\n있어볼까요?"
        case .chew: "평소처럼\n씹어볼까요?"
        case .ready: "내 리듬을 읽을\n준비가 됐어요"
        case .signalIssue: "신호를 충분히\n읽지 못했어요"
        }
    }

    private var stageMessage: String {
        switch store.stage {
        case .intro: "사람마다 움직임과 씹는 속도가 달라요.\n식사 전에 짧게 나만의 기준을 맞춰요."
        case .connection: "연결된 AirPods의 움직임 센서를 확인해요."
        case .rest: "고개와 턱에 힘을 빼고 정면을 봐주세요."
        case .chew: "준비한 음식을 평소 속도로 씹어주세요."
        case .ready: "다음 화면부터 평소처럼 식사하면 돼요."
        case .signalIssue: "괜찮아요. 착용 상태를 확인하고 다시 해볼게요."
        }
    }

    private var measurementStatusText: String {
        if store.measurementCompleted {
            return store.stage == .rest ? "편한 자세의 기준을 확인했어요" : "평소 씹기 리듬을 확인했어요"
        }
        if store.isMeasuring {
            let subject = store.stage == .chew ? "씹기 리듬" : "움직임"
            return "\(subject)을 읽고 있어요 · \(store.remainingSeconds)초"
        }
        return store.stage == .rest ? "준비되면 편하게 있어주세요" : "준비되면 평소처럼 씹어주세요"
    }

    private var primaryTitle: String {
        switch store.stage {
        case .intro:
            return "맞춤 측정 준비하기"
        case .connection:
            return "다음"
        case .rest, .chew:
            if store.isMeasuring { return "측정 중 · \(store.remainingSeconds)초" }
            return store.measurementCompleted ? "다음" : "10초 측정 시작"
        case .ready:
            return "식사 측정 시작"
        case .signalIssue:
            return "다시 측정"
        }
    }

    private var primaryIcon: String? {
        switch store.stage {
        case .intro: "waveform.path.ecg"
        case .connection: "arrow.right"
        case .rest, .chew: store.measurementCompleted ? "arrow.right" : "record.circle"
        case .ready: "fork.knife"
        case .signalIssue: "arrow.clockwise"
        }
    }

    private var primaryDisabled: Bool {
        store.isMeasuring || (store.stage == .connection && !store.isAirPodsConnected)
    }

    private func handlePrimaryAction() {
        switch store.stage {
        case .rest, .chew where !store.measurementCompleted:
            store.startMeasurement()
        case .ready:
            onComplete()
        case .signalIssue:
            store.retryChewMeasurement()
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
        _store = State(initialValue: MeasurementOnboardingStore(stage: stage, isAirPodsConnected: true))
    }

    var body: some View {
        MeasurementOnboardingView(
            store: store,
            onComplete: {},
            onSkip: {},
            onRetryConnection: { store.setAirPodsConnected(true) }
        )
        .task {
            if store.stage == .rest || store.stage == .chew {
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

private struct MeasurementProgressVisual: View {
    let progress: Double
    let remainingSeconds: Int
    let symbol: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.borderDefault, lineWidth: Metrics.ringWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: Metrics.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: AppMotion.durationSignal), value: progress)

            VStack(spacing: AppSpacing.one) {
                Image(systemName: symbol)
                    .font(.appFont(.regular, size: Metrics.progressIcon))
                    .foregroundStyle(tint)
                Text("\(remainingSeconds)")
                    .font(.appFont(.heavyTitleLarge))
                    .foregroundStyle(Color.textDefault)
                    .monospacedDigit()
                Text("초")
                    .font(.appFont(.boldCaption))
                    .foregroundStyle(Color.textMuted)
            }
        }
        .frame(width: Metrics.progressRing, height: Metrics.progressRing)
    }
}

private struct ChewRhythmVisual: View {
    let progress: Double
    let reduceMotion: Bool
    @State private var chewing = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.bgSurface)
                .frame(width: Metrics.signalCore, height: Metrics.signalCore)

            Image("DaramEating")
                .resizable()
                .scaledToFit()
                .frame(width: Metrics.squirrel, height: Metrics.squirrel)
                .scaleEffect(chewing && !reduceMotion ? 1.035 : 0.985)
                .animation(
                    .easeInOut(duration: AppMotion.durationChew).repeatForever(autoreverses: true),
                    value: chewing
                )

            Text("\(max(0, 10 - Int(progress * 10)))초")
                .font(.appFont(.boldCaption))
                .foregroundStyle(Color.textAction)
                .padding(.horizontal, AppSpacing.inner)
                .padding(.vertical, AppSpacing.oneHalf)
                .background(Color.bgSelected, in: Capsule())
        }
        .onAppear { chewing = true }
    }
}

private struct ReadyVisual: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.statusSuccessMuted)
                .frame(width: Metrics.signalCore, height: Metrics.signalCore)
            Image(systemName: "checkmark")
                .font(.appFont(.heavy, size: Metrics.heroIcon))
                .foregroundStyle(Color.statusSuccess)
        }
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
    static let progressRing: CGFloat = 152
    static let ringWidth: CGFloat = 9
    static let progressIcon: CGFloat = 28
    static let squirrel: CGFloat = 126
    static let progressHeight: CGFloat = 5
}
