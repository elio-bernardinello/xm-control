import Foundation

/// Two ready-made custom curves (app-level favorites).
///
/// The firmware only knows one writable curve: Custom (0xA0) with 10 bands
/// (-6…+6, low frequencies first: 31, 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k).
/// These favorites are just one-tap `setEqualizerBands` shortcuts: the
/// headphones switch to Custom and echo the curve back like any manual edit.
public enum CustomEqualizerCurve: String, CaseIterable, Identifiable {
    case film = "Film"
    case voix = "Voix"

    public var id: String { rawValue }

    /// 10 gains in -6…+6, low → high.
    public var bands: [Int] {
        switch self {
        case .film:
            // Immersion film/série sur Mac : basses présentes sans bouillie,
            // présence/dialogues maintenus, hauts aérés.
            return [4, 3, 2, 1, 0, 0, 1, 2, 3, 2]
        case .voix:
            // Voix/podcast/appels : coupe le ronron, pousse 500 Hz–2 kHz.
            return [-3, -2, -1, 0, 2, 3, 3, 2, 1, 0]
        }
    }

    public var detail: String {
        switch self {
        case .film: return "Basses + présence, pour films et séries."
        case .voix: return "Dialogues et podcasts mis en avant."
        }
    }
}
