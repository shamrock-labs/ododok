import SwiftUI

struct TabBarView: View {
    @Binding var selection: ContentView.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ContentView.Tab.allCases, id: \.self) { tab in
                let active = selection == tab
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 22, weight: active ? .bold : .regular))
                            .foregroundStyle(active ? Color.acorn600 : Color.ink400)
                        Text(tab.label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(active ? Color.acorn700 : Color.ink400)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.acorn100.opacity(0.6))
                .frame(height: 1)
        }
    }
}
