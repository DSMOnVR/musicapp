import SwiftUI
import UIKit
import CoreImage

enum Theme {
    static let bg = Color(red: 14 / 255, green: 14 / 255, blue: 16 / 255)
    static let card = Color(red: 27 / 255, green: 27 / 255, blue: 32 / 255)
    static let muted = Color(red: 168 / 255, green: 168 / 255, blue: 179 / 255)
    static let warn = Color(red: 1, green: 0.42, blue: 0.53)
}

enum AppTheme: String, CaseIterable, Identifiable {
    case lime, sunset, ocean, mono
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var accent: Color {
        switch self {
        case .lime: return Color(red: 0.83, green: 1.0, blue: 0.23)
        case .sunset: return Color(red: 1.0, green: 0.42, blue: 0.53)
        case .ocean: return Color(red: 0.23, green: 0.83, blue: 1.0)
        case .mono: return .white
        }
    }
}

@MainActor @Observable
final class ThemeStore {
    var theme: AppTheme { didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") } }
    var useArtColor: Bool { didSet { UserDefaults.standard.set(useArtColor, forKey: "useArtColor") } }
    var reduceMotion: Bool { didSet { UserDefaults.standard.set(reduceMotion, forKey: "reduceMotion") } }
    var artColor: Color?

    init() {
        let d = UserDefaults.standard
        theme = AppTheme(rawValue: d.string(forKey: "theme") ?? "") ?? .lime
        useArtColor = d.object(forKey: "useArtColor") as? Bool ?? true
        reduceMotion = d.bool(forKey: "reduceMotion")
    }

    var accent: Color { (useArtColor ? artColor : nil) ?? theme.accent }
    var motion: Animation? { reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.75) }

    func updateArt(_ data: Data?) { artColor = data.flatMap(ArtColor.vivid) }
}

enum ArtColor {
    /// Average color of the artwork, pushed bright enough to read on the dark background.
    static func vivid(_ data: Data) -> Color? {
        guard let cg = UIImage(data: data)?.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        guard let out = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent),
        ])?.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        CIContext().render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
            .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: s < 0.1 ? 0 : max(s, 0.55), brightness: max(b, 0.9))
    }
}
