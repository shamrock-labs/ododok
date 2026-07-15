import SwiftUI

struct ChewPersonalizationDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    let settings: PersonalizedChewDetectionSettings
    let onRemeasure: () -> Void
    let onReset: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.sectionGap) {
                    summary
                    diagnosticValues
                    amplitudeValues
                    actions
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.vertical, AppSpacing.six)
            }
            .background(Color.pageBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    AppSheetTitleText(title: "맞춤 측정 정보")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AppSheetTextActionButton(title: "닫기") { dismiss() }
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: AppSpacing.microGap) {
            Text("마지막 측정")
                .font(.appFont(.sectionTitle))
                .foregroundStyle(Color.textDefault)
            Text(KoDate.dateWithClock(
                settings.calibratedAt,
                dateFormat: "yyyy년 M월 d일 EEEE"
            ))
                .font(.appFont(.regularCallout))
                .foregroundStyle(Color.textMuted)
        }
    }

    private var diagnosticValues: some View {
        VStack(spacing: AppSpacing.none) {
            valueRow(title: "감지 기준 진폭", value: format(settings.minPeakAmplitude))
            Divider()
            valueRow(title: "맞춤 Y축 움직임 기준", value: format(gateThresholds.minimumRotationYStd))
            Divider()
            valueRow(title: "Y축 방향 비중 · 공통", value: format(gateThresholds.minimumRotationYDominance))
            Divider()
            valueRow(
                title: "Y축 잔진동 비중 · 공통",
                value: format(gateThresholds.minimumRotationYJitterBandDominance)
            )
            Divider()
            valueRow(title: "평소 씹기 간격", value: intervalText)
            Divider()
            valueRow(title: "대표 신호", value: "\(settings.calibrationPeakCount)개")
            Divider()
            valueRow(title: "리듬 감지", value: "\(settings.validationDetectedCount)회")
        }
    }

    @ViewBuilder
    private var amplitudeValues: some View {
        if let amplitudes = settings.calibrationAmplitudes, !amplitudes.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.gapTight) {
                Text("대표 Peak 진폭")
                    .font(.appFont(.sectionTitle))
                    .foregroundStyle(Color.textDefault)
                Text(amplitudes.map(format).joined(separator: "  "))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func valueRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.textMuted)
            Spacer()
            Text(value)
                .font(.appFont(.semiboldBody))
                .foregroundStyle(Color.textDefault)
        }
        .font(.appFont(.body))
        .padding(.vertical, AppSpacing.row)
    }

    private var actions: some View {
        VStack(spacing: AppSpacing.none) {
            Button {
                onRemeasure()
                dismiss()
            } label: {
                actionLabel(title: "다시 측정하기", systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier("RemeasureChewDetectionPersonalization")

            Divider()

            Button(role: .destructive) {
                onReset()
                dismiss()
            } label: {
                actionLabel(
                    title: "기본값으로 돌아가기",
                    systemImage: "arrow.uturn.backward",
                    color: .statusDanger
                )
            }
            .accessibilityIdentifier("ResetChewDetectionPersonalization")
        }
        .buttonStyle(.plain)
        .font(.appFont(.semiboldBody))
    }

    private func actionLabel(
        title: String,
        systemImage: String,
        color: Color = .textDefault
    ) -> some View {
        HStack(spacing: AppSpacing.gapTight) {
            Image(systemName: systemImage)
                .frame(width: AppSize.iconSmall)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.appFont(.semiboldCallout))
                .foregroundStyle(Color.textMuted)
        }
        .foregroundStyle(color)
        .padding(.vertical, AppSpacing.row)
        .contentShape(Rectangle())
    }

    private var intervalText: String {
        guard let interval = settings.naturalChewInterval else { return "기록 없음" }
        return String(format: "%.2f초", interval)
    }

    private var gateThresholds: ChewingGateThresholds {
        settings.gateThresholds ?? .standard
    }

    private func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}
