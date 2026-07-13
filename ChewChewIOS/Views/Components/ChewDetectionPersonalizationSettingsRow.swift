import SwiftUI

struct ChewDetectionPersonalizationSettingsRow: View {
    let isPersonalized: Bool

    var body: some View {
        AppSettingsRow(
            icon: "waveform.path.ecg",
            title: "씹기 감지 맞추기",
            subtitle: isPersonalized
                ? "내 씹기 신호에 맞춰 감지하고 있어요"
                : "AirPods로 내 씹기 신호를 맞춰요",
            value: isPersonalized ? "사용 중" : "설정 전",
            showsChevron: true
        )
    }
}
