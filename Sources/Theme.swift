import SwiftUI
import Observation
import UIKit
import CoreImage

@Observable
final class AppTheme {
    enum Preset: String, CaseIterable, Identifiable {
        case lime = "Lime", sunset = "Sunset", ocean = "Ocean", mono = "Mono", artwork = "Album art", rose = "Rose", violet = "Violet", emerald = "Emerald", ice = "Ice", midnight = "Midnight", graphite = "Graphite", crimson = "Crimson", gold = "Gold", lavender = "Lavender", mint = "Mint", neon = "Neon"
        var id: String { rawValue }
        var colors: [Color] {
            switch self {
            case .lime: return [Color(red: 0.72, green: 0.98, blue: 0.16), Color(red: 0.24, green: 0.42, blue: 0.12)]
            case .sunset: return [Color(red: 1, green: 0.39, blue: 0.48), Color(red: 1, green: 0.66, blue: 0.27)]
            case .ocean: return [Color(red: 0.10, green: 0.77, blue: 0.83), Color(red: 0.10, green: 0.29, blue: 0.62)]
            case .mono: return [Color(white: 0.72), Color(white: 0.34)]
            case .artwork: return [Color(red: 0.78, green: 0.31, blue: 0.77), Color(red: 0.35, green: 0.28, blue: 0.88)]
            case .rose: return [Color(red: 1.00, green: 0.42, blue: 0.62), Color(red: 0.48, green: 0.12, blue: 0.30)]
            case .violet: return [Color(red: 0.62, green: 0.42, blue: 1.00), Color(red: 0.20, green: 0.12, blue: 0.48)]
            case .emerald: return [Color(red: 0.18, green: 0.82, blue: 0.58), Color(red: 0.06, green: 0.30, blue: 0.24)]
            case .ice: return [Color(red: 0.40, green: 0.82, blue: 1.00), Color(red: 0.14, green: 0.34, blue: 0.62)]
            case .midnight: return [Color(red: 0.42, green: 0.48, blue: 0.70), Color(red: 0.08, green: 0.09, blue: 0.18)]
            case .graphite: return [Color(red: 0.62, green: 0.66, blue: 0.72), Color(red: 0.12, green: 0.14, blue: 0.18)]
            case .crimson: return [Color(red: 0.95, green: 0.16, blue: 0.28), Color(red: 0.30, green: 0.04, blue: 0.10)]
            case .gold: return [Color(red: 1.00, green: 0.76, blue: 0.24), Color(red: 0.48, green: 0.27, blue: 0.06)]
            case .lavender: return [Color(red: 0.78, green: 0.65, blue: 1.00), Color(red: 0.36, green: 0.22, blue: 0.62)]
            case .mint: return [Color(red: 0.48, green: 0.96, blue: 0.78), Color(red: 0.08, green: 0.42, blue: 0.34)]
            case .neon: return [Color(red: 0.82, green: 1.00, blue: 0.08), Color(red: 0.12, green: 0.48, blue: 0.92)]
            }
        }
    }

    var preset: Preset = .mono { didSet { save() } }
    var useArtworkColors = true { didSet { save() } }
    var appearance = "Dark" { didSet { save() } }
    var reduceMotion = false { didSet { save() } }
    var customAccentHex: String? { didSet { save() } }
    var artworkAccentHex: String? { didSet { save() } }
    var useCustomAccent = false { didSet { save() } }

    var customAccent: Color {
        get {
            guard let customAccentHex, let value = UInt64(customAccentHex, radix: 16) else { return preset.colors[0] }
            return Color(
                red: Double((value >> 16) & 0xff) / 255,
                green: Double((value >> 8) & 0xff) / 255,
                blue: Double(value & 0xff) / 255
            )
        }
        set {
            let ui = UIColor(newValue)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            customAccentHex = String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
            useCustomAccent = true
        }
    }

    var accent: Color {
        if useArtworkColors, let artworkAccentHex, let value = UInt64(artworkAccentHex, radix: 16) {
            return Color(red: Double((value >> 16) & 0xff) / 255,
                         green: Double((value >> 8) & 0xff) / 255,
                         blue: Double(value & 0xff) / 255)
        }
        return useCustomAccent ? customAccent : preset.colors[0]
    }

    func updateArtworkAccent(from data: Data?) {
        guard useArtworkColors, let data, let image = CIImage(data: data) else { return }
        let filter = CIFilter(name: "CIAreaAverage")
        filter?.setValue(image, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)
        guard let output = filter?.outputImage else { return }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        artworkAccentHex = String(format: "%02X%02X%02X", pixel[0], pixel[1], pixel[2])
    }

    init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "dsm.theme.preset"), let saved = Preset(rawValue: raw) { preset = saved }
        useArtworkColors = defaults.object(forKey: "dsm.theme.artwork") as? Bool ?? true
        appearance = defaults.string(forKey: "dsm.theme.appearance") ?? "Dark"
        reduceMotion = defaults.bool(forKey: "dsm.theme.reduceMotion")
        customAccentHex = defaults.string(forKey: "dsm.theme.customAccent")
        artworkAccentHex = defaults.string(forKey: "dsm.theme.artworkAccent")
        useCustomAccent = defaults.bool(forKey: "dsm.theme.useCustomAccent")
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(preset.rawValue, forKey: "dsm.theme.preset")
        defaults.set(useArtworkColors, forKey: "dsm.theme.artwork")
        defaults.set(appearance, forKey: "dsm.theme.appearance")
        defaults.set(reduceMotion, forKey: "dsm.theme.reduceMotion")
        defaults.set(customAccentHex, forKey: "dsm.theme.customAccent")
        defaults.set(artworkAccentHex, forKey: "dsm.theme.artworkAccent")
        defaults.set(useCustomAccent, forKey: "dsm.theme.useCustomAccent")
    }
}

enum Theme {
    static let bg = Color(red: 0.055, green: 0.055, blue: 0.065)
    static let card = Color(red: 0.105, green: 0.105, blue: 0.125)
    static let muted = Color(red: 0.62, green: 0.62, blue: 0.67)
}
