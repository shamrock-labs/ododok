import SwiftUI

struct MeasurementRhythmFeedbackVisual: View {
    let cueIndex: Int
    let cuePulseID: Int
    let cueHitID: Int
    let approachDuration: TimeInterval
    let reduceMotion: Bool

    @State private var noteProgress: CGFloat = 0
    @State private var targetFlash = false
    @State private var noteApproachTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: Metrics.sceneSpacing) {
            measurementFeedback
            rhythmTrack
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.sceneHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("씹기 감지 검증")
        .accessibilityValue("개인 리듬 안내 중")
        .accessibilityIdentifier("MeasurementRhythmFeedback")
    }

    private var measurementFeedback: some View {
        ZStack {
            SquirrelView(
                mood: .happy,
                hat: nil,
                glasses: nil,
                acc: nil,
                animKey: cueHitID,
                isEating: true
            )
            .scaleEffect(Metrics.squirrelScale)

        }
        .frame(height: Metrics.feedbackHeight)
    }

    private var rhythmTrack: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.trackRadius)
                    .fill(Color.bgSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.trackRadius)
                            .stroke(Color.tintInteractive.opacity(0.14), lineWidth: AppSize.border)
                    }

                laneGuides(trackWidth: proxy.size.width)
                targetZone(trackWidth: proxy.size.width)
                rhythmNote(trackWidth: proxy.size.width)

            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.trackRadius))
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.trackHeight)
        .onChange(of: cuePulseID) { _, _ in
            startNoteApproach()
        }
        .onChange(of: cueHitID) { _, _ in
            flashTarget()
        }
        .onAppear {
            if cuePulseID > 0 {
                startNoteApproach()
            }
        }
        .onDisappear {
            noteApproachTask?.cancel()
        }
    }

    private func laneGuides(trackWidth: CGFloat) -> some View {
        VStack(spacing: Metrics.laneSpacing) {
            ForEach(0..<2, id: \.self) { _ in
                Rectangle()
                    .fill(Color.borderDefault.opacity(0.55))
                    .frame(height: AppSize.border)
            }
        }
        .frame(width: trackWidth - Metrics.horizontalInset * 2)
    }

    private func targetZone(trackWidth: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: AppRadius.inner)
            .fill(Color.tintInteractive.opacity(targetFlash ? 0.22 : 0.08))
            .frame(width: Metrics.targetWidth, height: Metrics.targetHeight)
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.inner)
                    .stroke(
                        Color.tintInteractive.opacity(targetFlash ? 0.9 : 0.34),
                        lineWidth: targetFlash ? Metrics.targetActiveBorder : AppSize.border
                    )
            }
            .offset(x: targetOffset(trackWidth: trackWidth))
            .scaleEffect(targetFlash && !reduceMotion ? 1.04 : 1)
    }

    private func rhythmNote(trackWidth: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: AppRadius.inner)
            .fill(Color.tintInteractive)
            .frame(width: Metrics.noteWidth, height: Metrics.noteHeight)
            .shadow(
                color: Color.tintInteractive.opacity(0.18),
                radius: Metrics.noteShadowRadius,
                x: -Metrics.noteShadowX
            )
            .offset(x: noteOffset(trackWidth: trackWidth))
            .opacity(cueIndex == 0 ? 0 : 1)
    }

    private func noteOffset(trackWidth: CGFloat) -> CGFloat {
        let targetOffset = targetOffset(trackWidth: trackWidth)
        guard !reduceMotion else { return targetOffset }
        let startOffset = trackWidth / 2 - Metrics.horizontalInset - Metrics.noteWidth / 2
        return startOffset + (targetOffset - startOffset) * noteProgress
    }

    private func targetOffset(trackWidth: CGFloat) -> CGFloat {
        -trackWidth / 2 + Metrics.horizontalInset + Metrics.targetWidth / 2
    }

    private func startNoteApproach() {
        noteApproachTask?.cancel()
        guard !reduceMotion else {
            noteProgress = 1
            return
        }

        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            noteProgress = 0
        }

        noteApproachTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Metrics.animationStartDelayMilliseconds))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: approachDuration)) {
                noteProgress = 1
            }
        }
    }

    private func flashTarget() {
        targetFlash = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: AppMotion.durationStateChange)) {
                targetFlash = false
            }
        }
    }
}

private enum Metrics {
    static let sceneHeight: CGFloat = 180
    static let feedbackHeight: CGFloat = 116
    static let sceneSpacing: CGFloat = 6
    static let squirrelScale: CGFloat = 0.76
    static let trackHeight: CGFloat = 54
    static let trackRadius: CGFloat = 8
    static let horizontalInset: CGFloat = 18
    static let laneSpacing: CGFloat = 20
    static let targetWidth: CGFloat = 18
    static let targetHeight: CGFloat = 36
    static let targetActiveBorder: CGFloat = 2
    static let noteWidth: CGFloat = 16
    static let noteHeight: CGFloat = 28
    static let noteShadowRadius: CGFloat = 8
    static let noteShadowX: CGFloat = 3
    static let animationStartDelayMilliseconds = 17
}
