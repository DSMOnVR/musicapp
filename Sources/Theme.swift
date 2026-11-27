import SwiftUI
import Observation

@Observable
final class AppTheme {
    enum Preset: String, CaseIterable, Identifiable {
        case lime = "Lime", sunset = "Sunset", ocean = "Ocean", mono = "Mono", artwork = "Album art"
        var id: String { rawValue }
        var colors: [Color] {
            switch self {
            case .lime: return [Color(red: 0.72, green: 0.98, blue: 0.16), Color(red: 0.24, green: 0.42, blue: 0.12)]
            case .sunset: return [Color(red: 1, green: 0.39, blue: 0.48), Color(red: 1, green: 0.66, blue: 0.27)]
            case .ocean: return [Color(red: 0.10, green: 0.77, blue: 0.83), Color(red: 0.10, green: 0.29, blue: 0.62)]
            case .mono: return [Color(white: 0.72), Color(white: 0.34)]
            case .artwork: return [Color(red: 0.78, green: 0.31, blue: 0.77), Color(red: 0.35, green: 0.28, blue: 0.88)]
            }
        }
    }
    var preset: Preset = .mono
    var useArtworkColors = true
    var appearance = "Dark"
    var reduceMotion = false
    var accent: Color { preset.colors[0] }
}

enum Theme {
    static let bg = Color(red: 0.055, green: 0.055, blue: 0.065)
    static let card = Color(red: 0.105, green: 0.105, blue: 0.125)
    static let muted = Color(red: 0.62, green: 0.62, blue: 0.67)
}
