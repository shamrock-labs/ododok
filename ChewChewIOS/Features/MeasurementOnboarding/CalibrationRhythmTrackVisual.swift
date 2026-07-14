import SwiftUI

struct CalibrationRhythmTrackVisual: View {
    let cueIndex: Int
    let cueCount: Int
    let detectedCount: Int
    let cuePulseID: Int
    let cueHitID: Int
    let reduceMotion: Bool

    @State private var noteProgress: CGFloat = 0
    @State private var targetFlash = false

    var body: some View {
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

                VStack {
                    HStack {
                        Text("\(max(cueIndex, 0)) / \(cueCount)")
                            .font(.appFont(.boldCaption))
                            .foregroundStyle(Color.textMuted)
                            .monospacedDigit()
                        Spacer()
                        Label("\(detectedCount)", systemImage: "waveform.path")
                            .font(.appFont(.boldCaption))
                            .foregroundStyle(Color.tintInteractive)
                            .monospacedDigit()
                    }
                    Spacer()
                }
                .padding(AppSpacing.inner)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("씹기 리듬 보정")
        .accessibilityValue("안내 \(cueIndex)회 중 기준 신호 \(detectedCount)회")
        .accessibilityIdentifier("CalibrationRhythmTrack")
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
        let startOffset = trackWidth / 2 + Metrics.noteWidth / 2
        return startOffset + (targetOffset - startOffset) * noteProgress
    }

    private func targetOffset(trackWidth: CGFloat) -> CGFloat {
        -trackWidth / 2 + Metrics.horizontalInset + Metrics.targetWidth / 2
    }

    private func startNoteApproach() {
        noteProgress = reduceMotion ? 1 : 0
        guard !reduceMotion else { return }
        Task { @MainActor in
            await Task.yield()
            withAnimation(.linear(duration: Metrics.approachDuration)) {
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
    static let trackHeight: CGFloat = 150
    static let trackRadius: CGFloat = 8
    static let horizontalInset: CGFloat = 18
    static let laneSpacing: CGFloat = 48
    static let targetWidth: CGFloat = 26
    static let targetHeight: CGFloat = 82
    static let targetActiveBorder: CGFloat = 2
    static let noteWidth: CGFloat = 22
    static let noteHeight: CGFloat = 62
    static let noteShadowRadius: CGFloat = 8
    static let noteShadowX: CGFloat = 3
    static let approachDuration: TimeInterval = 1.2
}
