import SwiftUI

struct ThemesView: View {
    @Environment(ThemeStore.self) private var themes
    @Environment(PlayerEngine.self) private var engine

    var body: some View {
        @Bindable var store = themes
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Themes").font(.system(size: 32, weight: .bold)).padding(.top, 14)

                HStack(spacing: 12) {
                    ArtView(data: engine.currentTrack?.artworkData).frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(engine.currentTrack?.title ?? "Preview song").font(.system(size: 14, weight: .bold)).lineLimit(1)
                        Text("Preview").font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Image(systemName: "waveform").foregroundStyle(themes.accent).symbolEffect(.variableColor.iterative)
                    Image(systemName: "play.fill").foregroundStyle(Theme.bg).frame(width: 44, height: 44)
                        .background(themes.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(8)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(themes.accent, lineWidth: 3))

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    ForEach(AppTheme.allCases) { t in
                        Button { store.theme = t } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(LinearGradient(colors: [Theme.bg, t.accent], startPoint: .leading, endPoint: .trailing))
                                    .frame(height: 50)
                                Text(t.name).font(.system(size: 15, weight: .bold))
                            }
                            .padding(10)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(store.theme == t ? t.accent : Color.clear, lineWidth: 3)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Toggle("Color from album art", isOn: $store.useArtColor)
                Toggle("Reduce motion", isOn: $store.reduceMotion)
            }
            .font(.system(size: 15, weight: .bold))
            .tint(themes.accent)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}
