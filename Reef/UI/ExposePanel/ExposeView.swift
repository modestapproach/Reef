//
//  ExposeView.swift
//  Reef
//
//  Exposé grid panel UI: window thumbnails for a single app or browser profile.
//

import SwiftUI

enum ExposeMetrics {
    static let cardWidth: CGFloat = 264
    static let thumbnailHeight: CGFloat = 152
    static let cardHeight: CGFloat = thumbnailHeight + 28
    static let gridSpacing: CGFloat = 12
    static let gridPadding: CGFloat = 16
    static let headerHeight: CGFloat = 44
}

struct ExposeView: View {
    @ObservedObject var state: ExposeState
    var onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(state.applicationTitle)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(height: ExposeMetrics.headerHeight)

            Divider()
                .background(Color.white.opacity(0.2))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(ExposeMetrics.cardWidth), spacing: ExposeMetrics.gridSpacing),
                            count: max(1, state.columns)
                        ),
                        spacing: ExposeMetrics.gridSpacing
                    ) {
                        ForEach(Array(state.windows.enumerated()), id: \.offset) { index, window in
                            ExposeCard(
                                title: window.title,
                                thumbnail: window.cgWindowID.flatMap { state.thumbnails[$0] },
                                fallbackIcon: state.appIcon,
                                isSelected: index == state.selectedIndex
                            )
                            .id(index)
                            .onTapGesture {
                                onSelect(index)
                            }
                        }
                    }
                    .padding(ExposeMetrics.gridPadding)
                }
                .onChange(of: state.selectedIndex) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(state.selectedIndex, anchor: .center)
                    }
                }
            }
        }
        .background(Color.clear)
    }
}

struct ExposeCard: View {
    let title: String
    let thumbnail: CGImage?
    let fallbackIcon: NSImage?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.35))

                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(4)
                } else if let fallbackIcon {
                    Image(nsImage: fallbackIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                }
            }
            .frame(width: ExposeMetrics.cardWidth - 12, height: ExposeMetrics.thumbnailHeight)

            Text(title)
                .font(.caption)
                .foregroundColor(isSelected ? .white : .primary)
                .lineLimit(1)
                .frame(maxWidth: ExposeMetrics.cardWidth - 24)
        }
        .frame(width: ExposeMetrics.cardWidth, height: ExposeMetrics.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}
