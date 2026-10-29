import SonyHeadphonesKit

extension ListeningMode {
    var frenchLabel: String {
        switch self {
        case .standard: return "Standard"
        case .backgroundMusic: return "Musique de fond"
        case .cinema: return "Cinéma"
        }
    }
    var englishLabel: String {
        switch self {
        case .standard: return "Standard"
        case .backgroundMusic: return "Background Music"
        case .cinema: return "Cinema"
        }
    }
    var displayLabel: String { L(frenchLabel, englishLabel) }
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
    var englishLabel: String {
        switch self {
        case .off: return "Off"
        case .heavy: return "Heavy"
        case .clear: return "Clear"
        case .hard: return "Hard"
        case .soft: return "Soft"
        case .custom: return "Custom"
        }
    }
    var displayLabel: String { L(frenchLabel, englishLabel) }
}

extension BGMRoomSize {
    var frenchLabel: String {
        switch self {
        case .small: return "Chambre"
        case .middle: return "Salon"
        case .large: return "Café"
        }
    }
    var englishLabel: String {
        switch self {
        case .small: return "My Room"
        case .middle: return "Living Room"
        case .large: return "Cafe"
        }
    }
    var displayLabel: String { L(frenchLabel, englishLabel) }
}

extension SpeakToChatSensitivity {
    var frenchLabel: String {
        switch self {
        case .auto: return "Auto"
        case .high: return "Élevée"
        case .low: return "Faible"
        }
    }
    var englishLabel: String {
        switch self {
        case .auto: return "Auto"
        case .high: return "High"
        case .low: return "Low"
        }
    }
    var displayLabel: String { L(frenchLabel, englishLabel) }
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
    var englishLabel: String {
        switch self {
        case .short: return "Short delay"
        case .standard: return "Standard delay"
        case .long: return "Long delay"
        case .off: return "Manual"
        }
    }
    var displayLabel: String { L(frenchLabel, englishLabel) }
}
extension AutomaticPowerOffMode {
    var frenchLabel: String {
        switch self {
        case .whenTakenOff: return "Au retrait"
        case .off: return "Jamais"
        }
    }
    var englishLabel: String {
        switch self {
        case .whenTakenOff: return "When taken off"
        case .off: return "Never"
        }
    }
    var displayLabel: String { L(frenchLabel, englishLabel) }
}
