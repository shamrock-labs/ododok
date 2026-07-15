import SwiftUI

struct MeasurementRhythmFeedbackVisual: View {
    let cueIndex: Int
    let cuePulseID: Int
    let cueHitID: Int
    let approachDuration: TimeInterval
    let reduceMotion: Bool

    @State private var noteApproachStartedAt: Date?

    var body: some View {
        VStack(spacing: Metrics.sceneSpacing) {
            measurementFeedback
            rhythmTrack
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.sceneHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("씹기 리듬 안내")
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
                TimelineView(.animation(
                    minimumInterval: Metrics.animationFrameInterval,
                    paused: cueIndex == 0
                )) { timeline in
                    rhythmNote(trackWidth: proxy.size.width, now: timeline.date)
                }

            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.trackRadius))
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.trackHeight)
        .onChange(of: cuePulseID) { _, _ in
            startNoteApproach()
        }
        .onAppear {
            if cuePulseID > 0 {
                startNoteApproach()
            }
        }
        .onDisappear {
            noteApproachStartedAt = nil
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
            .fill(Color.tintInteractive.opacity(0.08))
            .frame(width: Metrics.targetWidth, height: Metrics.targetHeight)
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.inner)
                    .stroke(Color.tintInteractive.opacity(0.34), lineWidth: AppSize.border)
            }
            .offset(x: targetOffset(trackWidth: trackWidth))
    }

    private func rhythmNote(trackWidth: CGFloat, now: Date) -> some View {
        RoundedRectangle(cornerRadius: AppRadius.inner)
            .fill(Color.tintInteractive)
            .frame(width: Metrics.noteWidth, height: Metrics.noteHeight)
            .shadow(
                color: Color.tintInteractive.opacity(reduceMotion ? 0 : 0.18),
                radius: Metrics.noteShadowRadius,
                x: -Metrics.noteShadowX
            )
            .offset(x: noteOffset(trackWidth: trackWidth, now: now))
            .opacity(cueIndex == 0 ? 0 : 1)
    }

    private func noteOffset(trackWidth: CGFloat, now: Date) -> CGFloat {
        let targetOffset = targetOffset(trackWidth: trackWidth)
        let startOffset = trackWidth / 2 - Metrics.horizontalInset - Metrics.noteWidth / 2
        let progress = noteProgress(at: now)
        return startOffset + (targetOffset - startOffset) * progress
    }

    private func noteProgress(at now: Date) -> CGFloat {
        guard let noteApproachStartedAt, approachDuration > 0 else { return 0 }
        return min(max(now.timeIntervalSince(noteApproachStartedAt) / approachDuration, 0), 1)
    }

    private func targetOffset(trackWidth: CGFloat) -> CGFloat {
        -trackWidth / 2 + Metrics.horizontalInset + Metrics.targetWidth / 2
    }

    private func startNoteApproach() {
        noteApproachStartedAt = Date()
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
    static let noteWidth: CGFloat = 16
    static let noteHeight: CGFloat = 28
    static let noteShadowRadius: CGFloat = 8
    static let noteShadowX: CGFloat = 3
    static let animationFrameInterval: TimeInterval = 1 / 60
}
