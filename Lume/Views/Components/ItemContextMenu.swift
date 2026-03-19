import SwiftUI

struct ItemContextMenu: ViewModifier {
    let item: BaseItemDto
    let session: SessionManager
    var onPlay: (() -> Void)? = nil
    var onDetail: (() -> Void)? = nil
    var onRefresh: (() -> Void)? = nil

    @State private var isFavorite: Bool
    @State private var isPlayed: Bool

    init(item: BaseItemDto, session: SessionManager, onPlay: (() -> Void)? = nil, onDetail: (() -> Void)? = nil, onRefresh: (() -> Void)? = nil) {
        self.item = item
        self.session = session
        self.onPlay = onPlay
        self.onDetail = onDetail
        self.onRefresh = onRefresh
        self._isFavorite = State(initialValue: item.userData?.isFavorite ?? false)
        self._isPlayed = State(initialValue: item.userData?.played ?? false)
    }

    func body(content: Content) -> some View {
        content.contextMenu {
            if let onPlay {
                Button {
                    onPlay()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
            }

            if let onDetail {
                Button {
                    onDetail()
                } label: {
                    Label("View Details", systemImage: "info.circle")
                }
            }

            Divider()

            Button {
                toggleFavorite()
            } label: {
                Label(
                    isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: isFavorite ? "heart.slash.fill" : "heart.fill"
                )
            }

            Button {
                togglePlayed()
            } label: {
                Label(
                    isPlayed ? "Mark as Unwatched" : "Mark as Watched",
                    systemImage: isPlayed ? "eye.slash.fill" : "eye.fill"
                )
            }
        }
    }

    private func toggleFavorite() {
        guard let itemId = item.id else { return }
        Task {
            do {
                let result = try await session.toggleFavorite(itemId: itemId, isFavorite: isFavorite)
                isFavorite = result.isFavorite ?? isFavorite
            } catch {
                // Silently fail — could show an alert
            }
        }
    }

    private func togglePlayed() {
        guard let itemId = item.id else { return }
        Task {
            do {
                let result = try await session.togglePlayed(itemId: itemId, isPlayed: isPlayed)
                isPlayed = result.played ?? isPlayed
            } catch {
                // Silently fail
            }
        }
    }
}

extension View {
    func itemContextMenu(item: BaseItemDto, session: SessionManager, onPlay: (() -> Void)? = nil, onDetail: (() -> Void)? = nil, onRefresh: (() -> Void)? = nil) -> some View {
        modifier(ItemContextMenu(item: item, session: session, onPlay: onPlay, onDetail: onDetail, onRefresh: onRefresh))
    }
}
