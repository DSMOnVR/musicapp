import SwiftUI
import WidgetKit

struct ThemesView: View {
    @Environment(AppTheme.self) private var theme
    @State private var iconMessage: String?
    @AppStorage("widget.style", store: UserDefaults(suiteName: "group.com.example.musicapp.shared")) private var widgetStyle = "Midnight"

    var body: some View {
        @Bindable var theme = theme
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Themes").font(.system(size: 34, weight: .bold))
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: [theme.accent, theme.preset.colors[1]], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 58, height: 58)
                    VStack(alignment: .leading) {
                        Text("Your current look").font(.headline)
                        Text(theme.useCustomAccent ? "Custom color" : theme.preset.rawValue).font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Image(systemName: "waveform").foregroundStyle(theme.accent)
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.accent, lineWidth: 2))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(AppTheme.Preset.allCases) { preset in
                        Button {
                            theme.preset = preset
                            theme.useCustomAccent = false
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(height: 76)
                                HStack {
                                    Text(preset.rawValue).font(.headline)
                                    Spacer()
                                    if theme.preset == preset && !theme.useCustomAccent {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
                                    }
                                }
                            }
                            .padding(12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Custom accent").font(.headline)
                    ColorPicker("Choose your own color", selection: $theme.customAccent, supportsOpacity: false)
                        .tint(theme.accent)
                    Toggle("Use custom accent", isOn: $theme.useCustomAccent).tint(theme.accent)
                    Text("Your theme and custom color are saved automatically.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 12) {
                    Text("App icon").font(.headline)
                    HStack(spacing: 12) {
                        iconChoice("Default", name: nil, colors: [.black, Color(white: 0.38)])
                        iconChoice("Mono", name: "DSMMono", colors: [Color(white: 0.78), Color(white: 0.22)])
                        iconChoice("Blue", name: "DSMBlue", colors: [.cyan, .blue])
                        iconChoice("Purple", name: "DSMPurple", colors: [.purple, .pink])
                    }
                    if let iconMessage { Text(iconMessage).font(.caption).foregroundStyle(Theme.muted) }
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Home & Lock Screen widgets").font(.headline)
                    Picker("Widget appearance", selection: $widgetStyle) {
                        Text("Midnight").tag("Midnight")
                        Text("Ocean").tag("Ocean")
                        Text("Violet").tag("Violet")
                        Text("Rose").tag("Rose")
                        Text("Gold").tag("Gold")
                    }
                    .pickerStyle(.menu)
                    Text("Add DSM Music to your Home Screen or Lock Screen, then choose a widget size. Changes refresh the widget.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                .onChange(of: widgetStyle) { _, _ in WidgetCenter.shared.reloadAllTimelines() }

                Toggle("Color from album artwork", isOn: $theme.useArtworkColors).tint(theme.accent)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Appearance").font(.headline)
                    Picker("Appearance", selection: $theme.appearance) {
                        Text("Dark").tag("Dark")
                        Text("Light").tag("Light")
                        Text("Auto").tag("Auto")
                    }.pickerStyle(.segmented)
                }
                Toggle("Reduce motion", isOn: $theme.reduceMotion).tint(theme.accent)
            }
            .padding(22)
        }
        .foregroundStyle(.white)
    }
    private func iconChoice(_ title: String, name: String?, colors: [Color]) -> some View {
        Button {
            guard UIApplication.shared.supportsAlternateIcons else {
                iconMessage = "Alternate icons are not available on this device."
                return
            }
            UIApplication.shared.setAlternateIconName(name) { error in
                iconMessage = error == nil ? "\(title) icon selected." : "Couldn't change the app icon: \(error!.localizedDescription)"
            }
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 13)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Image(systemName: "waveform").font(.title2.bold()).foregroundStyle(.white))
                    .frame(width: 58, height: 58)
                Text(title).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

}

struct MiniPlayer: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(AppTheme.self) private var appTheme
    var open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 10) {
                    if let track = engine.currentTrack { ArtworkView(track: track).frame(width: 46, height: 46) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(engine.currentTrack?.title ?? "Not playing").font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                        Text(engine.currentTrack?.artist ?? "").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            Image(systemName: "waveform").foregroundStyle(appTheme.accent)
            Button { engine.togglePlayPause() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3).foregroundStyle(.white).frame(width: 42, height: 44)
            }.buttonStyle(.plain)
        }
        .padding(9)
        .background(Theme.card, in: Capsule())
    }
}
