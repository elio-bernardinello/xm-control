import SwiftUI
import SonyHeadphonesKit

/// The app mark. The only place the brand draws its own shape, shared with the Dock icon.
struct XMMark: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.96, blue: 0.92), Color(red: 0.91, green: 0.87, blue: 0.80)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(Color(red: 0.47, green: 0.39, blue: 0.24).opacity(0.22), lineWidth: 0.75)
            HeadphoneImage().padding(size * 0.12)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct XMIdentity: View {
    var modelLabel: String = "SONY · WH-1000X"
    var body: some View {
        HStack(spacing: 10) {
            XMMark()
            VStack(alignment: .leading, spacing: 2) {
                Text("XM Control").font(.headline)
                Text(modelLabel).font(.caption2).tracking(1.2).foregroundStyle(.secondary)
            }
        }
    }
}

extension ListeningMode {
    var detail: String { displayDetail }
    var displayDetail: String {
        switch self {
        case .standard: return L("Votre son, tout simplement.", "Just your sound.")
        case .backgroundMusic: return L("La musique vous entoure.", "Music all around you.")
        case .cinema: return L("Entrez dans le film.", "Step into the film.")
        }
    }
    var shortDetail: String {
        switch self {
        case .standard: return L("Son original", "Original sound")
        case .backgroundMusic: return L("Ambiance douce", "Soft ambience")
        case .cinema: return L("Son immersif", "Immersive sound")
        }
    }
}
