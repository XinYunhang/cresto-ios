import SwiftUI
import SwiftData
import UIKit

struct TarotView: View {
    @Environment(\.modelContext) private var context

    /// 今天的记录，由 RootView 保证已创建
    let draw: DailyTarot?

    @State private var isFlipped = true
    @State private var isShuffling = false
    @State private var isDealt = false
    @State private var isMetaVisible = true
    @State private var isBusy = false
    @State private var showingDeck = false

    init(draw: DailyTarot?) {
        self.draw = draw
    }

    private var card: TarotCard { draw?.card ?? TarotDeck.major[0] }
    private var reversed: Bool { draw?.isReversed ?? false }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.cardGap) {
                header

                DeckView(
                    card: card,
                    isFlipped: isFlipped,
                    isShuffling: isShuffling,
                    isDealt: isDealt
                )
                .onTapGesture { redraw() }
                .padding(.top, 12)
                .padding(.bottom, 10)

                metaBlock
                    .opacity(isMetaVisible ? 1 : 0)
                    .offset(y: isMetaVisible ? 0 : 6)

                readingCard

                Button(action: redraw) {
                    Text("重新抽一张")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                        )
                }
                .buttonStyle(PressableStyle())
                .disabled(isBusy)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 132)
        }
        .sheet(isPresented: $showingDeck) {
            TarotDeckSheet()
        }
    }

    // MARK: 页头

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("每日一抽 · \(Date().formatted(.dateTime.month().day()))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text("塔罗")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .tracking(-0.5)
            }
            Spacer()
            Button {
                showingDeck = true
            } label: {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.05)))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("牌库")
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    // MARK: 文字

    private var metaBlock: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(card.name)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text(card.en)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text("\(card.positionText(reversed: reversed)) · 大阿尔卡纳 \(card.roman)")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 6)
            HStack(spacing: 6) {
                ForEach(card.keywords(reversed: reversed), id: \.self) { keyword in
                    AccentChip(text: keyword)
                }
            }
            .padding(.top, 14)
        }
        .animation(.easeOut(duration: 0.45), value: isMetaVisible)
    }

    private var readingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("牌义").cardLabel()
                Spacer()
                Text(reversed ? "逆位" : "正位")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.bottom, 11)
            Text(card.text(reversed: reversed))
                .font(.system(size: 13))
                .lineSpacing(5)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 抽牌

    /// 收牌 → 洗牌 → 发牌 → 翻面
    private func redraw() {
        guard !isBusy, let draw else { return }
        isBusy = true
        isMetaVisible = false

        withAnimation(.easeIn(duration: 0.35)) {
            isFlipped = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isShuffling = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                TarotService.redraw(draw, in: context)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    isShuffling = false
                    isDealt = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.82)) {
                        isFlipped = true
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            isDealt = false
                        }
                        withAnimation(.easeOut(duration: 0.4)) {
                            isMetaVisible = true
                        }
                        isBusy = false
                    }
                }
            }
        }
    }
}

// MARK: - 牌堆

struct DeckView: View {
    let card: TarotCard
    let isFlipped: Bool
    let isShuffling: Bool
    let isDealt: Bool

    private let cardWidth: CGFloat = 180
    private let cardHeight: CGFloat = 270

    var body: some View {
        ZStack {
            ghost(rotation: 6, offset: CGSize(width: 7, height: 7), opacity: 0.35)
                .offset(x: isShuffling ? 18 : 0, y: isShuffling ? -2 : 0)
                .rotationEffect(.degrees(isShuffling ? 11 : 6))

            ghost(rotation: -5, offset: CGSize(width: -6, height: 4), opacity: 0.55)
                .offset(x: isShuffling ? -16 : 0, y: isShuffling ? -4 : 0)
                .rotationEffect(.degrees(isShuffling ? -9 : -5))

            flippingCard
                .offset(y: isDealt ? -18 : 0)
                .scaleEffect(isDealt ? 1.03 : 1)
        }
        .frame(width: cardWidth, height: cardHeight)
        .frame(height: 330)
        .animation(.spring(response: 0.55, dampingFraction: 0.75), value: isShuffling)
        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: isDealt)
    }

    private func ghost(rotation: Double, offset: CGSize, opacity: Double) -> some View {
        CardArt(name: "card-back")
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
            )
            .rotationEffect(.degrees(rotation))
            .offset(offset)
            .opacity(opacity)
    }

    private var flippingCard: some View {
        ZStack {
            CardArt(name: "card-back")
                .opacity(isFlipped ? 0 : 1)

            CardArt(name: card.slug)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.9), radius: 30, y: 18)
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
    }
}

// MARK: - 牌库

struct TarotDeckSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: TarotCard?

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(TarotDeck.major) { card in
                        Button {
                            selected = card
                        } label: {
                            VStack(spacing: 6) {
                                CardArt(name: card.slug)
                                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                                    )
                                Text(card.name)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Theme.bg)
            .navigationTitle("大阿尔卡纳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.foregroundStyle(Theme.text)
                }
            }
            .tint(Theme.ink)
            .sheet(item: $selected) { card in
                TarotCardDetail(card: card)
            }
        }
        .presentationBackground(Theme.bg)
    }
}

struct TarotCardDetail: View {
    @Environment(\.dismiss) private var dismiss
    let card: TarotCard

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                CardArt(name: card.slug)
                    .frame(width: 168, height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .padding(.top, 12)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(card.name).font(.system(size: 21, weight: .medium)).foregroundStyle(Theme.text)
                    Text(card.en).font(.system(size: 12, design: .serif)).foregroundStyle(Theme.textTertiary)
                }
                Text("大阿尔卡纳 \(card.roman)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)

                meaningBlock("正位", keywords: card.uprightKeywords, text: card.uprightText)
                meaningBlock("逆位", keywords: card.reversedKeywords, text: card.reversedText)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 30)
        }
        .background(Theme.bg)
        .presentationBackground(Theme.bg)
        .overlay(alignment: .topTrailing) {
            Button("关闭") { dismiss() }
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .padding(16)
        }
    }

    private func meaningBlock(_ title: String, keywords: [String], text: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).cardLabel()
            HStack(spacing: 6) {
                ForEach(keywords, id: \.self) { keyword in
                    AccentChip(text: keyword)
                }
            }
            Text(text)
                .font(.system(size: 13))
                .lineSpacing(5)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

// MARK: - 卡面

struct CardArt: View {
    let name: String
    var grayscale = false

    var body: some View {
        Group {
            if let image = Self.load(name) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Color.white.opacity(0.06)
                    Image(systemName: "sparkles")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .saturation(grayscale ? 0 : 1)
    }

    /// 优先找资源目录，其次找工程里拖进来的 Resources/Cards/*.webp
    static func load(_ name: String) -> UIImage? {
        if let image = UIImage(named: name) { return image }
        for ext in ["webp", "png", "jpg"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }
        return nil
    }
}
