import SwiftUI

/// 상점 탭. 출시 전까지는 placeholder만 노출 — 실제 그리드 UI는
/// `ShopGridView`에 보존되어 있고 출시 시 `Self.isEnabled = true` 로 전환하면
/// 즉시 활성화. 시뮬레이터에서 미리 보려면 `-enableShop` launch argument로 실행.
struct ShopView: View {
    private static let isEnabled: Bool =
        ProcessInfo.processInfo.arguments.contains("-enableShop")

    var body: some View {
        if Self.isEnabled {
            ShopGridView()
        } else {
            ShopPlaceholderView()
        }
    }
}

// MARK: - Placeholder (출시 전 노출)

private struct ShopPlaceholderView: View {
    var body: some View {
        VStack(spacing: AppSpacing.verticalLoose) {
            header
            Spacer(minLength: AppSpacing.six)
            comingSoonCard
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.cardOuter)
        .padding(.top, AppSpacing.cardOuter)
        .padding(.bottom, AppSpacing.cardOuterBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        AppHeaderView(eyebrow: "도토리 사용처", title: "상점", subtitle: "꾸미기 아이템을 준비 중이에요") {
            HeaderMetricPill(icon: .acorn, value: "준비중", tint: .acorn700)
        }
    }

    private var comingSoonCard: some View {
        AppCard(padding: AppSpacing.dialogH, radius: AppRadius.page, elevation: .flat) {
            AppEmptyState(
                spacing: AppSpacing.verticalLoose,
                title: "상점을 준비하고 있어요",
                message: "도토리로 다람쥐를 꾸미는 기능을 준비 중이에요.\n그 전엔 저작 트래킹에 집중해요.",
                titleFont: .heavyTitleLarge,
                messageFont: .semiboldLabel
            ) {
                Image("RealDaram")
                    .resizable()
                    .scaledToFit()
                    .frame(height: Metrics.heroImageHeight)
                    .scaleEffect(AppArtwork.daramContentScale)
            }
        }
    }

}

// MARK: - Grid view (출시 시 활성화)

private struct ShopGridView: View {
    @Environment(AppState.self) private var state

    @State private var category: Category = .all
    @State private var toast: AppToastMessage?

    enum Category: String, CaseIterable, Identifiable {
        case all, hat, glasses, acc
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:     "전체"
            case .hat:     "모자"
            case .glasses: "안경"
            case .acc:     "액세서리"
            }
        }

        var icon: String {
            switch self {
            case .all:     "square.grid.2x2.fill"
            case .hat:     "graduationcap.fill"
            case .glasses: "eyeglasses"
            case .acc:     "sparkles"
            }
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: AppSpacing.cell),
        GridItem(.flexible(), spacing: AppSpacing.cell)
    ]

    var body: some View {
        VStack(spacing: AppSpacing.four) {
            header
            categoryStrip
            itemGrid
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, AppSpacing.three)
        .padding(.bottom, AppSpacing.cardOuterBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .appToast($toast)
    }

    // MARK: Header

    private var header: some View {
        AppHeaderView(eyebrow: "다람쥐 꾸미기", title: "상점", subtitle: "모은 도토리로 아이템을 골라요") {
            HeaderMetricPill(icon: .acorn, value: state.points.koLocale, tint: .acorn700)
        }
    }

    // MARK: Category chips

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.two) {
                ForEach(Category.allCases) { cat in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { category = cat }
                    } label: {
                        HStack(spacing: AppSpacing.oneHalf) {
                            Image(systemName: cat.icon)
                                .font(.appFont(.boldMicro))
                            Text(cat.label)
                                .font(.appFont(.boldCaption))
                        }
                        .padding(.horizontal, AppSpacing.cell)
                        .padding(.vertical, AppSpacing.two)
                        .foregroundStyle(category == cat ? Color.textActionInverse : Color.textMuted)
                        .background(
                            category == cat
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Color.acorn500, Color.acorn600],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(Color.bgSurface),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Item grid

    private var filteredItems: [ShopItem] {
        switch category {
        case .all:     return ShopItem.all
        case .hat:     return ShopItem.all.filter { $0.type == .hat }
        case .glasses: return ShopItem.all.filter { $0.type == .glasses }
        case .acc:     return ShopItem.all.filter { $0.type == .acc }
        }
    }

    private var itemGrid: some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.cell) {
            ForEach(filteredItems) { item in
                itemCard(item)
            }
        }
        .padding(.bottom, AppSpacing.six)
    }

    private func itemCard(_ item: ShopItem) -> some View {
        let owned = state.isOwned(item)
        let equipped = state.isEquipped(item)
        let canAfford = state.points >= item.price

        return VStack(spacing: AppSpacing.inner) {
            HStack {
                if item.rarity == .rare {
                    AppBadge(
                        text: "희귀",
                        foreground: Color.textActionInverse,
                        background: Color.statusWarning,
                        font: .heavyMicro
                    )
                } else {
                    Color.clear.frame(height: AppSpacing.cell)
                }
                Spacer()
                if equipped {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.appFont(.regularLabel))
                        .foregroundStyle(Color.statusSuccess)
                } else if owned {
                    AppBadge(text: "보유")
                }
            }

            Text(item.emoji)
                .font(.appFont(.regularEmojiHuge))
                .frame(height: Metrics.itemEmojiHeight)

            VStack(spacing: AppSpacing.half) {
                Text(item.name)
                    .font(.appFont(.boldCallout))
                    .foregroundStyle(Color.textDefault)
                    .lineLimit(1)
                Text(typeLabel(item.type))
                    .font(.appFont(.semiboldCaption))
                    .foregroundStyle(Color.textSubtle)
            }

            actionButton(for: item, owned: owned, equipped: equipped, canAfford: canAfford)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppSpacing.three)
        .padding(.vertical, AppSpacing.cell)
        .background(
            LinearGradient(
                colors: equipped
                    ? [Color.statusSuccessMuted, .cream]
                    : [Color.bgSurface, .cream],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: AppRadius.container)
        )
        .appElevation(.flat)
    }

    private func typeLabel(_ k: ShopItem.Kind) -> String {
        switch k {
        case .hat:     "모자"
        case .glasses: "안경"
        case .acc:     "액세서리"
        }
    }

    @ViewBuilder
    private func actionButton(
        for item: ShopItem,
        owned: Bool,
        equipped: Bool,
        canAfford: Bool
    ) -> some View {
        if equipped {
            Button {
                state.unequip(item.type)
                toast = AppToastMessage("장착 해제됨", kind: .info)
            } label: {
                pillLabel("장착 중", style: .sage)
            }
            .buttonStyle(.plain)
        } else if owned {
            Button {
                state.equip(item)
                toast = AppToastMessage("\(item.name) 장착", kind: .success)
            } label: {
                pillLabel("장착하기", style: .acorn)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                switch state.buyItem(item) {
                case .success:
                    toast = AppToastMessage("\(item.name) 구매 완료", kind: .success)
                case .notEnoughPoints:
                    toast = AppToastMessage("도토리가 부족해요", kind: .warning)
                case .alreadyOwned:
                    break
                }
            } label: {
                pricePill(item.price, enabled: canAfford)
            }
            .buttonStyle(.plain)
            .disabled(!canAfford)
        }
    }

    private enum PillStyle { case acorn, sage }

    private func pillLabel(_ text: String, style: PillStyle) -> some View {
        Text(text)
            .font(.appFont(.boldCaption))
            .foregroundStyle(Color.textActionInverse)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.two)
            .background(
                LinearGradient(
                    colors: style == .acorn
                        ? [Color.acorn400, Color.acorn600]
                        : [Color.sage400, Color.sage600],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: AppRadius.inner)
            )
    }

    private func pricePill(_ price: Int, enabled: Bool) -> some View {
        HStack(spacing: AppSpacing.one) {
            OpenIconView(icon: .acorn, color: enabled ? .textActionInverse : .ink400, lineWidth: 2.2)
                .frame(width: Metrics.itemIcon, height: Metrics.itemIcon)
            Text(price.koLocale)
                .font(.appFont(.boldCaption))
                .monospacedDigit()
        }
        .foregroundStyle(enabled ? Color.textActionInverse : Color.textSubtle)
        .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.two)
        .background(
            enabled
                ? AnyShapeStyle(LinearGradient(
                    colors: [Color.acorn400, Color.acorn600],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                : AnyShapeStyle(Color.borderDefault),
            in: RoundedRectangle(cornerRadius: AppRadius.inner)
        )
    }

}

#Preview("Placeholder (기본)") {
    ShopView()
        .environment(AppState())
        .background(Color.pageBackground)
}

private enum Metrics {
    static let heroImageHeight: CGFloat = 150
    static let itemEmojiHeight: CGFloat = 60
    static let itemIcon = AppSize.iconXSmall
}
