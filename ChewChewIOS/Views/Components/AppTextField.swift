import SwiftUI

struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    var submitLabel: SubmitLabel = .done
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
            .font(.appFont(.inputText))
            .foregroundStyle(Color.inputText)
            .padding(.horizontal, AppSpacing.inputH)
            .padding(.vertical, AppSpacing.inputV)
            .background(Color.inputBg.opacity(0.85), in: RoundedRectangle(cornerRadius: AppRadius.element))
            .appElevation(.medium)
    }
}
