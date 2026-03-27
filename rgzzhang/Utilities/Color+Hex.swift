import SwiftUI

extension Color {
    /// Create a `Color` from a 6-digit hex string like `"#RRGGBB"` or `"RRGGBB"`.
    init(hex: String, alpha: Double = 1.0) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let hexValue = cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
        let r, g, b: Double

        if hexValue.count == 6, let intVal = UInt64(hexValue, radix: 16) {
            r = Double((intVal & 0xFF0000) >> 16) / 255.0
            g = Double((intVal & 0x00FF00) >> 8) / 255.0
            b = Double(intVal & 0x0000FF) / 255.0
        } else {
            // Fallback to system gray if parsing fails.
            r = 0.6
            g = 0.6
            b = 0.6
        }

        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

