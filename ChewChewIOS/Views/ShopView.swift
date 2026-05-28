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
        VStack(spacing: 18) {
            header
            Spacer(minLength: 24)
            comingSoonCard
            Spacer(minLength: 24)
            roadmapCard
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("출시 예정")
                    .font(.appFont(.medium, size: 11))
                    .foregroundStyle(Color.ink400)
                Text("상점")
                    .font(.appFont(.bold, size: 24))
                    .foregroundStyle(Color.ink800)
            }
            Spacer()
        }
    }

    private var comingSoonCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.butter200.opacity(0.45))
                    .frame(width: 150, height: 150)
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 108, height: 108)
                    .neuoShadow(.sm)
                Text("상점은\n준비 중")
                    .font(.appFont(.heavy, size: 20))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.acorn700)
            }

            VStack(spacing: 6) {
                Text("상점을 준비하고 있어요")
                    .font(.appFont(.heavy, size: 21))
                    .foregroundStyle(Color.ink800)
                    .multilineTextAlignment(.center)
                Text("도토리로 다람쥐를 꾸미는 기능을 준비 중이에요.\n우선은 저작 트래킹과 목표 달성에 집중해주세요.")
                    .font(.appFont(.medium, size: 13))
                    .foregroundStyle(Color.ink600)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.white, .cream, Color.acorn50],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .neuoShadow(.md)
    }

    private var roadmapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bag")
                    .font(.appFont(.bold, size: 18))
                    .foregroundStyle(Color.butter600)
                    .frame(width: 38, height: 38)
                    .background(Color.butter100, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("준비 중인 아이템")
                        .font(.appFont(.bold, size: 12))
                        .foregroundStyle(Color.ink800)
                    Text("모자 · 안경 · 액세서리 · 도토리 팩")
                        .font(.appFont(.medium, size: 11))
                        .foregroundStyle(Color.ink400)
                }

                Spacer(minLength: 0)
            }

            Text("저작 트래킹이 안정화되면 상점이 열릴 예정이에요.")
                .font(.appFont(.regular, size: 12))
                .foregroundStyle(Color.ink600)
                .lineSpacing(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }
}

// MARK: - Grid view (출시 시 활성화)

private struct ShopGridView: View {
    @Environment(AppState.self) private var state

    @State private var category: Category = .all
    @State private var toast: ToastMessage?
    @State private var toastTimer: Timer?

    enum Category: String, CaseIterable, Identifiable {
        case all, hat, glasses, acc, pack
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:     "전체"
            case .hat:     "모자"
            case .glasses: "안경"
            case .acc:     "액세서리"
            case .pack:    "도토리팩"
            }
        }

        var icon: String {
            switch self {
            case .all:     "square.grid.2x2.fill"
            case .hat:     "graduationcap.fill"
            case .glasses: "eyeglasses"
            case .acc:     "sparkles"
            case .pack:    "shippingbox.fill"
            }
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 16) {
            header
            categoryStrip

            if category == .pack {
                packList
            } else {
                itemGrid
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) { toastView }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("다람쥐 꾸미기")
                    .font(.appFont(.medium, size: 11))
                    .foregroundStyle(Color.ink400)
                Text("상점")
                    .font(.appFont(.bold, size: 24))
                    .foregroundStyle(Color.ink800)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("🌰").font(.appFont(.regular, size: 16))
                Text(state.points.koLocale)
                    .font(.appFont(.bold, size: 14))
                    .foregroundStyle(Color.acorn700)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white, in: Capsule())
            .neuoShadow(.sm)
        }
    }

    // MARK: Category chips

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Category.allCases) { cat in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { category = cat }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: cat.icon)
                                .font(.appFont(.bold, size: 11))
                            Text(cat.label)
                                .font(.appFont(.bold, size: 12))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(category == cat ? .white : Color.ink600)
                        .background(
                            category == cat
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Color.acorn500, Color.acorn600],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(Color.white),
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
        case .pack:    return []
        }
    }

    private var itemGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(filteredItems) { item in
                itemCard(item)
            }
        }
        .padding(.bottom, 24)
    }

    private func itemCard(_ item: ShopItem) -> some View {
        let owned = state.isOwned(item)
        let equipped = state.isEquipped(item)
        let canAfford = state.points >= item.price

        return VStack(spacing: 10) {
            HStack {
                if item.rarity == .rare {
                    Text("희귀")
                        .font(.appFont(.heavy, size: 9))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            LinearGradient(
                                colors: [Color.butter500, Color.butter600],
                                startPoint: .leading, endPoint: .trailing),
                            in: Capsule()
                        )
                } else {
                    Color.clear.frame(height: 14)
                }
                Spacer()
                if equipped {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.appFont(.regular, size: 14))
                        .foregroundStyle(Color.sage500)
                } else if owned {
                    Text("보유")
                        .font(.appFont(.bold, size: 9))
                        .foregroundStyle(Color.acorn700)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.acorn50, in: Capsule())
                }
            }

            Text(item.emoji)
                .font(.appFont(.regular, size: 44))
                .frame(height: 60)

            VStack(spacing: 2) {
                Text(item.name)
                    .font(.appFont(.bold, size: 13))
                    .foregroundStyle(Color.ink800)
                    .lineLimit(1)
                Text(typeLabel(item.type))
                    .font(.appFont(.medium, size: 10))
                    .foregroundStyle(Color.ink400)
            }

            actionButton(for: item, owned: owned, equipped: equipped, canAfford: canAfford)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: equipped
                    ? [Color.sage50, .cream]
                    : [.white, .cream],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .neuoShadow(.sm)
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
                showToast(ToastMessage(text: "장착 해제됨", kind: .info))
            } label: {
                pillLabel("장착 중", style: .sage)
            }
            .buttonStyle(.plain)
        } else if owned {
            Button {
                state.equip(item)
                showToast(ToastMessage(text: "\(item.name) 장착", kind: .success))
            } label: {
                pillLabel("장착하기", style: .acorn)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                switch state.buyItem(item) {
                case .success:
                    showToast(ToastMessage(text: "\(item.name) 구매 완료", kind: .success))
                case .notEnoughPoints:
                    showToast(ToastMessage(text: "도토리가 부족해요", kind: .warn))
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
            .font(.appFont(.bold, size: 12))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: style == .acorn
                        ? [Color.acorn400, Color.acorn600]
                        : [Color.sage400, Color.sage600],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 10)
            )
    }

    private func pricePill(_ price: Int, enabled: Bool) -> some View {
        HStack(spacing: 4) {
            Text("🌰").font(.appFont(.regular, size: 11))
            Text(price.koLocale)
                .font(.appFont(.bold, size: 12))
                .monospacedDigit()
        }
        .foregroundStyle(enabled ? .white : Color.ink400)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            enabled
                ? AnyShapeStyle(LinearGradient(
                    colors: [Color.acorn400, Color.acorn600],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                : AnyShapeStyle(Color.ink100),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    // MARK: AcornPack list

    private var packList: some View {
        VStack(spacing: 12) {
            ForEach(AcornPack.all) { pack in
                packCard(pack)
            }
            Text("도토리팩 효과는 추후 자동 연동돼요. 지금은 보유 카운트만 누적됩니다.")
                .font(.appFont(.regular, size: 11))
                .foregroundStyle(Color.ink400)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.horizontal, 12)
        }
        .padding(.bottom, 24)
    }

    private func packCard(_ pack: AcornPack) -> some View {
        let count = state.ownedAcornPacks[pack.id] ?? 0
        let canAfford = state.points >= pack.price

        return HStack(spacing: 14) {
            Text(pack.emoji)
                .font(.appFont(.regular, size: 32))
                .frame(width: 56, height: 56)
                .background(Color.butter100, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pack.name)
                        .font(.appFont(.bold, size: 14))
                        .foregroundStyle(Color.ink800)
                    if count > 0 {
                        Text("보유 \(count)")
                            .font(.appFont(.bold, size: 9))
                            .foregroundStyle(Color.acorn700)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.acorn50, in: Capsule())
                    }
                }
                Text(pack.effect)
                    .font(.appFont(.medium, size: 11))
                    .foregroundStyle(Color.ink400)
            }

            Spacer()

            Button {
                switch state.buyAcornPack(pack) {
                case .success:
                    showToast(ToastMessage(text: "\(pack.name) 획득", kind: .success))
                case .notEnoughPoints:
                    showToast(ToastMessage(text: "도토리가 부족해요", kind: .warn))
                case .alreadyOwned:
                    break
                }
            } label: {
                HStack(spacing: 4) {
                    Text("🌰").font(.appFont(.regular, size: 11))
                    Text(pack.price.koLocale)
                        .font(.appFont(.bold, size: 12))
                        .monospacedDigit()
                }
                .foregroundStyle(canAfford ? .white : Color.ink400)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    canAfford
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color.acorn400, Color.acorn600],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color.ink100),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canAfford)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }

    // MARK: Toast

    private struct ToastMessage: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let kind: Kind
        enum Kind { case success, warn, info }
    }

    private func showToast(_ msg: ToastMessage) {
        withAnimation { toast = msg }
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { _ in
            withAnimation { toast = nil }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let t = toast {
            HStack(spacing: 8) {
                Image(systemName: toastIcon(t.kind))
                    .font(.appFont(.bold, size: 13))
                Text(t.text)
                    .font(.appFont(.bold, size: 13))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(toastBG(t.kind), in: RoundedRectangle(cornerRadius: 16))
            .softShadow(.lg)
            .padding(.bottom, 110)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private func toastIcon(_ k: ToastMessage.Kind) -> String {
        switch k {
        case .success: "checkmark.circle.fill"
        case .warn:    "exclamationmark.triangle.fill"
        case .info:    "info.circle.fill"
        }
    }

    private func toastBG(_ k: ToastMessage.Kind) -> Color {
        switch k {
        case .success: Color.sage500
        case .warn:    Color.blush500
        case .info:    Color.ink800
        }
    }
}

#Preview("Placeholder (기본)") {
    ShopView()
        .environment(AppState())
        .background(LinearGradient.appBackground)
}
