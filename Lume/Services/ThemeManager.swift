import SwiftUI

enum ThemeFlavor: String, CaseIterable, Identifiable, Codable {
    // Catppuccin
    case mocha = "Catppuccin Mocha"
    case macchiato = "Catppuccin Macchiato"
    case frappe = "Catppuccin Frappé"
    case latte = "Catppuccin Latte"
    // Nord
    case nordDark = "Nord Polar Night"
    case nordLight = "Nord Snow Storm"
    // Dracula
    case dracula = "Dracula"
    // Gruvbox
    case gruvboxDark = "Gruvbox Dark"
    case gruvboxLight = "Gruvbox Light"
    // Tokyo Night
    case tokyoNight = "Tokyo Night"
    case tokyoNightStorm = "Tokyo Night Storm"
    case tokyoNightDay = "Tokyo Night Day"
    // Rosé Pine
    case rosePine = "Rosé Pine"
    case rosePineMoon = "Rosé Pine Moon"
    case rosePineDawn = "Rosé Pine Dawn"
    // Solarized
    case solarizedDark = "Solarized Dark"
    case solarizedLight = "Solarized Light"
    // One
    case oneDark = "One Dark"
    // Kanagawa
    case kanagawa = "Kanagawa"
    // Midnight
    case midnight = "Midnight"
    // Sunset
    case sunset = "Sunset"

    var id: String { rawValue }

    var accentColor: Color {
        switch self {
        case .mocha:            return Color(hex: "89b4fa")
        case .macchiato:        return Color(hex: "8aadf4")
        case .frappe:           return Color(hex: "8caaee")
        case .latte:            return Color(hex: "1e66f5")
        case .nordDark:         return Color(hex: "88c0d0")
        case .nordLight:        return Color(hex: "5e81ac")
        case .dracula:          return Color(hex: "bd93f9")
        case .gruvboxDark:      return Color(hex: "d79921")
        case .gruvboxLight:     return Color(hex: "b57614")
        case .tokyoNight:       return Color(hex: "7aa2f7")
        case .tokyoNightStorm:  return Color(hex: "7aa2f7")
        case .tokyoNightDay:    return Color(hex: "2e7de9")
        case .rosePine:         return Color(hex: "c4a7e7")
        case .rosePineMoon:     return Color(hex: "c4a7e7")
        case .rosePineDawn:     return Color(hex: "907aa9")
        case .solarizedDark:    return Color(hex: "268bd2")
        case .solarizedLight:   return Color(hex: "268bd2")
        case .oneDark:          return Color(hex: "61afef")
        case .kanagawa:         return Color(hex: "7e9cd8")
        case .midnight:         return Color(hex: "82aaff")
        case .sunset:           return Color(hex: "ff6e6e")
        }
    }

    var secondaryAccent: Color {
        switch self {
        case .mocha:            return Color(hex: "cba6f7")
        case .macchiato:        return Color(hex: "c6a0f6")
        case .frappe:           return Color(hex: "ca9ee6")
        case .latte:            return Color(hex: "8839ef")
        case .nordDark:         return Color(hex: "81a1c1")
        case .nordLight:        return Color(hex: "81a1c1")
        case .dracula:          return Color(hex: "ff79c6")
        case .gruvboxDark:      return Color(hex: "b8bb26")
        case .gruvboxLight:     return Color(hex: "79740e")
        case .tokyoNight:       return Color(hex: "bb9af7")
        case .tokyoNightStorm:  return Color(hex: "bb9af7")
        case .tokyoNightDay:    return Color(hex: "9854f1")
        case .rosePine:         return Color(hex: "ebbcba")
        case .rosePineMoon:     return Color(hex: "ea9a97")
        case .rosePineDawn:     return Color(hex: "d7827e")
        case .solarizedDark:    return Color(hex: "2aa198")
        case .solarizedLight:   return Color(hex: "2aa198")
        case .oneDark:          return Color(hex: "c678dd")
        case .kanagawa:         return Color(hex: "957fb8")
        case .midnight:         return Color(hex: "c792ea")
        case .sunset:           return Color(hex: "fab387")
        }
    }

    var backgroundColor: Color {
        switch self {
        case .mocha:            return Color(hex: "1e1e2e")
        case .macchiato:        return Color(hex: "24273a")
        case .frappe:           return Color(hex: "303446")
        case .latte:            return Color(hex: "eff1f5")
        case .nordDark:         return Color(hex: "2e3440")
        case .nordLight:        return Color(hex: "eceff4")
        case .dracula:          return Color(hex: "282a36")
        case .gruvboxDark:      return Color(hex: "282828")
        case .gruvboxLight:     return Color(hex: "fbf1c7")
        case .tokyoNight:       return Color(hex: "1a1b26")
        case .tokyoNightStorm:  return Color(hex: "24283b")
        case .tokyoNightDay:    return Color(hex: "e1e2e7")
        case .rosePine:         return Color(hex: "191724")
        case .rosePineMoon:     return Color(hex: "232136")
        case .rosePineDawn:     return Color(hex: "faf4ed")
        case .solarizedDark:    return Color(hex: "002b36")
        case .solarizedLight:   return Color(hex: "fdf6e3")
        case .oneDark:          return Color(hex: "282c34")
        case .kanagawa:         return Color(hex: "1f1f28")
        case .midnight:         return Color(hex: "0f111a")
        case .sunset:           return Color(hex: "1e1e2e")
        }
    }

    var secondaryBackground: Color {
        switch self {
        case .mocha:            return Color(hex: "181825")
        case .macchiato:        return Color(hex: "1e2030")
        case .frappe:           return Color(hex: "292c3c")
        case .latte:            return Color(hex: "e6e9ef")
        case .nordDark:         return Color(hex: "3b4252")
        case .nordLight:        return Color(hex: "e5e9f0")
        case .dracula:          return Color(hex: "44475a")
        case .gruvboxDark:      return Color(hex: "3c3836")
        case .gruvboxLight:     return Color(hex: "ebdbb2")
        case .tokyoNight:       return Color(hex: "24283b")
        case .tokyoNightStorm:  return Color(hex: "1a1b26")
        case .tokyoNightDay:    return Color(hex: "d5d6db")
        case .rosePine:         return Color(hex: "1f1d2e")
        case .rosePineMoon:     return Color(hex: "2a273f")
        case .rosePineDawn:     return Color(hex: "f2e9de")
        case .solarizedDark:    return Color(hex: "073642")
        case .solarizedLight:   return Color(hex: "eee8d5")
        case .oneDark:          return Color(hex: "21252b")
        case .kanagawa:         return Color(hex: "2a2a37")
        case .midnight:         return Color(hex: "1a1c25")
        case .sunset:           return Color(hex: "28283e")
        }
    }

    var textColor: Color {
        switch self {
        case .mocha:            return Color(hex: "cdd6f4")
        case .macchiato:        return Color(hex: "cad3f5")
        case .frappe:           return Color(hex: "c6d0f5")
        case .latte:            return Color(hex: "4c4f69")
        case .nordDark:         return Color(hex: "eceff4")
        case .nordLight:        return Color(hex: "2e3440")
        case .dracula:          return Color(hex: "f8f8f2")
        case .gruvboxDark:      return Color(hex: "ebdbb2")
        case .gruvboxLight:     return Color(hex: "3c3836")
        case .tokyoNight:       return Color(hex: "c0caf5")
        case .tokyoNightStorm:  return Color(hex: "c0caf5")
        case .tokyoNightDay:    return Color(hex: "3760bf")
        case .rosePine:         return Color(hex: "e0def4")
        case .rosePineMoon:     return Color(hex: "e0def4")
        case .rosePineDawn:     return Color(hex: "575279")
        case .solarizedDark:    return Color(hex: "839496")
        case .solarizedLight:   return Color(hex: "657b83")
        case .oneDark:          return Color(hex: "abb2bf")
        case .kanagawa:         return Color(hex: "dcd7ba")
        case .midnight:         return Color(hex: "b2ccd6")
        case .sunset:           return Color(hex: "cdd6f4")
        }
    }

    var subtleText: Color {
        switch self {
        case .latte, .nordLight, .gruvboxLight, .tokyoNightDay, .rosePineDawn, .solarizedLight:
            return textColor.opacity(0.5)
        default:
            return textColor.opacity(0.45)
        }
    }

    var isDark: Bool {
        switch self {
        case .latte, .nordLight, .gruvboxLight, .tokyoNightDay, .rosePineDawn, .solarizedLight:
            return false
        default:
            return true
        }
    }

    var category: ThemeCategory {
        switch self {
        case .mocha, .macchiato, .frappe, .latte: return .catppuccin
        case .nordDark, .nordLight: return .nord
        case .dracula: return .dracula
        case .gruvboxDark, .gruvboxLight: return .gruvbox
        case .tokyoNight, .tokyoNightStorm, .tokyoNightDay: return .tokyoNight
        case .rosePine, .rosePineMoon, .rosePineDawn: return .rosePine
        case .solarizedDark, .solarizedLight: return .solarized
        case .oneDark: return .oneDark
        case .kanagawa: return .kanagawa
        case .midnight: return .midnight
        case .sunset: return .sunset
        }
    }
}

enum ThemeCategory: String, CaseIterable, Identifiable {
    case catppuccin = "Catppuccin"
    case nord = "Nord"
    case dracula = "Dracula"
    case gruvbox = "Gruvbox"
    case tokyoNight = "Tokyo Night"
    case rosePine = "Rosé Pine"
    case solarized = "Solarized"
    case oneDark = "One Dark"
    case kanagawa = "Kanagawa"
    case midnight = "Midnight"
    case sunset = "Sunset"

    var id: String { rawValue }

    var flavors: [ThemeFlavor] {
        ThemeFlavor.allCases.filter { $0.category == self }
    }

    var icon: String {
        switch self {
        case .catppuccin: return "cup.and.saucer.fill"
        case .nord: return "snowflake"
        case .dracula: return "moon.fill"
        case .gruvbox: return "leaf.fill"
        case .tokyoNight: return "building.2.fill"
        case .rosePine: return "camera.macro"
        case .solarized: return "sun.max.fill"
        case .oneDark: return "circle.lefthalf.filled"
        case .kanagawa: return "water.waves"
        case .midnight: return "moon.stars.fill"
        case .sunset: return "sunset.fill"
        }
    }
}

@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    var currentFlavor: ThemeFlavor = .mocha {
        didSet {
            UserDefaults.standard.set(currentFlavor.rawValue, forKey: "lume_theme_flavor")
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "lume_theme_flavor"),
           let flavor = ThemeFlavor(rawValue: saved) {
            self.currentFlavor = flavor
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 128, 128, 128)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
