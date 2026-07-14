import SwiftUI

struct AirPodsConnectionReadinessVisual: View {
    let isConnected: Bool
    let isPreparing: Bool

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

            Image(systemName: statusIcon)
                .font(.appFont(.regular, size: Metrics.statusIcon))
                .foregroundStyle(isConnected ? Color.statusSuccess : Color.statusWarning)
                .background(Color.bgPage, in: Circle())
        }
    }

    private var statusIcon: String {
        if isPreparing { return "waveform.circle.fill" }
        return isConnected ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }
}

private enum Metrics {
    static let signalCore: CGFloat = 132
    static let heroIcon: CGFloat = 54
    static let statusIcon: CGFloat = 34
}
