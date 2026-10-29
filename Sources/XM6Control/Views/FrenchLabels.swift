import SonyHeadphonesKit

extension ListeningMode {
    var frenchLabel: String {
        switch self {
        case .standard: return "Standard"
        case .backgroundMusic: return "Musique de fond"
        case .cinema: return "Cinéma"
        }
    }
    var symbol: String {
        switch self {
        case .standard: return "headphones"
        case .backgroundMusic: return "music.note"
        case .cinema: return "film"
        }
    }
}

extension EqualizerPreset {
    var frenchLabel: String {
        switch self {
        case .off: return "Désactivé"
        case .heavy: return "Graves"
        case .clear: return "Clair"
        case .hard: return "Dynamique"
        case .soft: return "Doux"
        case .custom: return "Personnalisé"
        }
    }
}

extension BGMRoomSize {
    var frenchLabel: String {
        switch self {
        case .small: return "Chambre"
        case .middle: return "Salon"
        case .large: return "Café"
        }
    }
}

extension SpeakToChatSensitivity {
    var frenchLabel: String {
        switch self {
        case .auto: return "Auto"
        case .high: return "Élevée"
        case .low: return "Faible"
        }
    }
}
extension SpeakToChatTimeout {
    var frenchLabel: String {
        switch self {
        case .short: return "Délai court"
        case .standard: return "Délai standard"
        case .long: return "Délai long"
        case .off: return "Manuellement"
        }
    }
}
extension AutomaticPowerOffMode {
    var frenchLabel: String {
        switch self {
        case .whenTakenOff: return "Au retrait"
        case .off: return "Jamais"
        }
    }
}
