//
//  ExposeView.swift
//  Reef
//
//  Full-screen exposé overlay: the binding's windows tiled as large previews.
//

import SwiftUI

struct ExposeView: View {
    @ObservedObject var state: ExposeState
    var onSelect: (Int) -> Void
    var onCancel: () -> Void

    private let edgePadding: CGFloat = 48
    private let tileSpacing: CGFloat = 24
    private let headerHeight: CGFloat = 56

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dimmed backdrop; clicking it cancels.
                Color.black.opacity(0.5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onCancel()
                    }

                VStack(spacing: 0) {
                    header

                    tiles(in: geometry.size)
                        .padding(.horizontal, edgePadding)
                        .padding(.bottom, edgePadding)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(state.applicationTitle)
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            if !state.hasScreenAccess {
                Text("Enable Screen Recording for Reef in System Settings → Privacy & Security to see window previews")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(height: headerHeight + (state.hasScreenAccess ? 0 : 20))
        .padding(.top, 12)
    }

    private func tiles(in size: CGSize) -> some View {
        let rowChunks = state.rowChunks
        let rows = CGFloat(max(1, rowChunks.count))
        let columns = CGFloat(max(1, state.columns))

        let availableWidth = size.width - edgePadding * 2
        let availableHeight = size.height - headerHeight - 12 - edgePadding
        let cellWidth = (availableWidth - tileSpacing * (columns - 1)) / columns
        let cellHeight = (availableHeight - tileSpacing * (rows - 1)) / rows

        return VStack(spacing: tileSpacing) {
            Spacer(minLength: 0)

            ForEach(Array(rowChunks.enumerated()), id: \.offset) { _, rowIndices in
                HStack(spacing: tileSpacing) {
                    ForEach(rowIndices, id: \.self) { index in
                        ExposeTile(
                            title: state.windows[index].title,
                            thumbnail: state.windows[index].cgWindowID.flatMap { state.thumbnails[$0] },
                            fallbackIcon: state.appIcon,
                            isSelected: index == state.selectedIndex
                        )
                        .frame(maxWidth: cellWidth, maxHeight: cellHeight)
                        .onTapGesture {
                            onSelect(index)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)
        }
    }
}

struct ExposeTile: View {
    let title: String
    let thumbnail: CGImage?
    let fallbackIcon: NSImage?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(title)
                .font(.callout)
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.black.opacity(0.55))
                )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
                .overlay {
                    if let fallbackIcon {
                        Image(nsImage: fallbackIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 96, maxHeight: 96)
                    }
                }
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        }
    }
}
