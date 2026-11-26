import SwiftUI

struct ArtView: View {
    let data: Data?
    var body: some View {
        Color.clear
            .overlay {
                if let data, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .clipped()
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 20, weight: .bold)).padding(.top, 26).padding(.bottom, 12)
    }
}

struct EmptyHint: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 16)).foregroundStyle(Theme.muted).padding(.top, 30)
    }
}
