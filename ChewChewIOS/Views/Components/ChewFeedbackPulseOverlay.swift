import SwiftUI

struct ChewFeedbackPulseOverlay: View {
    let triggerKey: Int
    let isActive: Bool

    @State private var pulses: [ChewFeedbackPulse] = []

    var body: some View {
        ForEach(pulses) { pulse in
            ChewFeedbackPulseView(pulse: pulse)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: triggerKey) { oldKey, newKey in
            guard isActive, newKey != oldKey else { return }
            addPulse(for: newKey)
        }
        .onChange(of: isActive) { _, active in
            if !active { pulses.removeAll() }
        }
        .onDisappear {
            pulses.removeAll()
        }
    }

    private func addPulse(for key: Int) {
        let pulse = ChewFeedbackPulse.make(for: key)
        withAnimation(.spring(
            response: AppMotion.springFastResponse,
            dampingFraction: AppMotion.springDampingFraction
        )) {
            pulses.append(pulse)
            if pulses.count > Metrics.maximumPulseCount {
                pulses.removeFirst(pulses.count - Metrics.maximumPulseCount)
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Metrics.pulseLifetime))
            withAnimation(.easeOut(duration: AppMotion.durationButtonPress)) {
                pulses.removeAll { $0.id == pulse.id }
            }
        }
    }
}

private struct ChewFeedbackPulse: Identifiable, Equatable {
    let id = UUID()
    let offset: CGSize

    static func make(for key: Int) -> ChewFeedbackPulse {
        let positions = [
            CGSize(width: -76, height: -52),
            CGSize(width: 72, height: -62),
            CGSize(width: -58, height: 34),
            CGSize(width: 66, height: 28),
        ]
        let index = ((key % positions.count) + positions.count) % positions.count
        return ChewFeedbackPulse(offset: positions[index])
    }
}

private struct ChewFeedbackPulseView: View {
    let pulse: ChewFeedbackPulse

    @State private var appeared = false
    @State private var disappearing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.acorn100.opacity(0.92))
                .frame(width: Metrics.bubbleSize, height: Metrics.bubbleSize)
                .overlay {
                    Circle()
                        .stroke(Color.surface.opacity(0.9), lineWidth: AppSize.border)
                }
                .shadow(color: Color.highlightShadow.opacity(0.2), radius: 8, x: 0, y: 5)

            OpenIconView(icon: .acorn, color: .rewardAcorn, lineWidth: 2.1)
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
        }
        .scaleEffect(appeared ? (disappearing ? 0.82 : 1.05) : 0.45)
        .opacity(appeared ? (disappearing ? 0 : 1) : 0)
        .offset(
            x: pulse.offset.width,
            y: pulse.offset.height + (appeared ? -18 : 4) + (disappearing ? -16 : 0)
        )
        .animation(
            .spring(
                response: AppMotion.springPlayfulResponse,
                dampingFraction: AppMotion.springPlayfulDamping
            ),
            value: appeared
        )
        .animation(.easeOut(duration: AppMotion.durationStateChange), value: disappearing)
        .onAppear {
            appeared = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Metrics.disappearDelay))
                disappearing = true
            }
        }
    }
}

private enum Metrics {
    static let maximumPulseCount = 4
    static let pulseLifetime: TimeInterval = 0.95
    static let disappearDelay: TimeInterval = 0.68
    static let bubbleSize: CGFloat = 30
    static let iconSize: CGFloat = 17
}
