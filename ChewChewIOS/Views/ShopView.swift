import SwiftUI

struct ShopView: View {
    @Environment(AppState.self) private var state

    @State private var category: Category = .costume
    @State private var toast: ToastMessage?

    enum Category: String, CaseIterable {
        case costume, snack
        var label: String {
            switch self {
            case .costume: "의상 꾸미기"
            case .snack:   "도토리 상점"
            }
        }
    }

    struct ToastMessage: Equatable {
        enum Kind { case ok, err }
        let kind: Kind
        let text: String
    }

    var body: some View {
        VStack(spacing: 20) {
            header
            acornBalanceCard
            earnHighlights
            categorySwitch

            if category == .costume {
                costumeGrid
            } else {
                snackList
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .overlay(alignment: .bottom) {
            if let t = toast {
                toastView(t)
                    .padding(.bottom, 110)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("앱테크")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.ink400)
                Text("상점 & 꾸미기")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.ink800)
            }
            Spacer()
        }
    }

    // MARK: Acorn balance

    private var acornBalanceCard: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color.butter400, Color.acorn300, Color.acorn400],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 28))

            Text("🌰")
                .font(.system(size: 140))
                .opacity(0.20)
                .offset(x: 220, y: 60)

            VStack(alignment: .leading, spacing: 10) {
                Text("보유 도토리")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(state.points.koLocale)
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("개")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                HStack(spacing: 8) {
                    Button {} label: {
                        HStack(spacing: 4) {
                            Image(systemName: "gift.fill").font(.system(size: 11))
                            Text("친구에게 선물").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color.acorn700)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    Button {} label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right").font(.system(size: 11))
                            Text("획득 내역").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .frame(height: 170)
        .softShadow(.lg)
    }

    // MARK: Earn highlights

    private var earnHighlights: some View {
        HStack(spacing: 8) {
            earnCard("🍽️", "식사 1회",   "+50")
            earnCard("🎯", "목표 달성",   "+200")
            earnCard("🔥", "7일 스트릭", "+500")
        }
    }

    private func earnCard(_ emoji: String, _ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(emoji).font(.system(size: 20))
            Text(label).font(.system(size: 10)).foregroundStyle(Color.ink400)
            Text(value).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.acorn600)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .neuoShadow(.sm)
    }

    // MARK: Category switch

    private var categorySwitch: some View {
        HStack(spacing: 4) {
            ForEach(Category.allCases, id: \.self) { c in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { category = c }
                } label: {
                    Text(c.label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(category == c ? .white : Color.ink400)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            category == c
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Color.acorn400, Color.acorn500],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .neuoShadow(.sm)
    }

    // MARK: Costume grid

    private var costumeGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ShopItem.all) { item in
                costumeCard(item)
            }
        }
    }

    private func costumeCard(_ item: ShopItem) -> some View {
        let owned = state.owned.contains(item.id)
        let equipped = state.equippedID(for: item.type) == item.id
        return VStack(spacing: 10) {
            ZStack {
                LinearGradient(
                    colors: [Color.acorn50, .cream, Color.sage50],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Text(item.emoji).font(.system(size: 44))

                VStack {
                    HStack {
                        rarityTag(item.rarity)
                        Spacer()
                        if equipped {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                                Text("착용중").font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.sage500, in: Capsule())
                        }
                    }
                    Spacer()
                }
                .padding(6)
            }
            .frame(height: 96)

            Text(item.name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.ink800)
                .frame(maxWidth: .infinity, alignment: .leading)

            if owned {
                Button {
                    let nowEquipped = state.toggleEquip(item)
                    show(.init(kind: .ok, text: nowEquipped ? "\(item.name) 착용!" : "\(item.name) 벗었어요"))
                } label: {
                    Text(equipped ? "벗기" : "착용하기")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(equipped ? Color.blush500 : Color.sage600)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(equipped ? Color.blush100 : Color.sage100, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(PressableButtonStyle())
            } else {
                Button {
                    if state.buy(item) {
                        show(.init(kind: .ok, text: "\(item.name) 구매 완료!"))
                    } else {
                        show(.init(kind: .err, text: "도토리가 부족해요 🌰"))
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("🌰").font(.system(size: 11))
                        Text(item.price.koLocale).font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color.acorn700)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.acorn100, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }

    private func rarityTag(_ rarity: ShopItem.Rarity) -> some View {
        let (tag, bg, fg): (String, Color, Color) = {
            switch rarity {
            case .common: return ("기본", Color.acorn100,  Color.acorn700)
            case .rare:   return ("레어", Color.butter100, Color.butter600)
            }
        }()
        return Text(tag)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bg, in: Capsule())
    }

    // MARK: Snack list

    private var snackList: some View {
        VStack(spacing: 12) {
            ForEach(AcornPack.all) { pack in
                HStack(spacing: 12) {
                    Text(pack.emoji)
                        .font(.system(size: 28))
                        .frame(width: 56, height: 56)
                        .background(
                            LinearGradient(
                                colors: [Color.butter50, Color.acorn50],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 14)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pack.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.ink800)
                        Text(pack.effect).font(.system(size: 10)).foregroundStyle(Color.ink400)
                    }
                    Spacer()
                    Button {
                        if state.consume(pack) {
                            show(.init(kind: .ok, text: "\(pack.name) 사용! \(pack.effect)"))
                        } else {
                            show(.init(kind: .err, text: "도토리가 부족해요 🌰"))
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text("🌰").font(.system(size: 11))
                            Text(pack.price.koLocale).font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Color.acorn700)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.acorn100, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
                .neuoShadow(.sm)
            }
        }
    }

    // MARK: Toast

    private func toastView(_ t: ToastMessage) -> some View {
        Text(t.text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                t.kind == .err ? Color.blush500 : Color.ink800,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .softShadow(.lg)
    }

    private func show(_ t: ToastMessage) {
        withAnimation { toast = t }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { toast = nil }
        }
    }
}
