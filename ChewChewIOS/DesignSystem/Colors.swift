import SwiftUI

extension Color {
    static let cream    = Color(hex: 0xFAF7F2)
    static let cream2   = Color(hex: 0xF5EDE0)

    static let acorn50  = Color(hex: 0xFBF3E8)
    static let acorn100 = Color(hex: 0xF5E2C8)
    static let acorn200 = Color(hex: 0xE8C99B)
    static let acorn300 = Color(hex: 0xD9B07F)
    static let acorn400 = Color(hex: 0xC8956D)
    static let acorn500 = Color(hex: 0xB07F58)
    static let acorn600 = Color(hex: 0x9C6E47)
    static let acorn700 = Color(hex: 0x7B532E)
    static let acorn800 = Color(hex: 0x5C3E25)

    static let sage50   = Color(hex: 0xEDF6EE)
    static let sage100  = Color(hex: 0xD4ECD7)
    static let sage200  = Color(hex: 0xB8DEC0)
    static let sage400  = Color(hex: 0x7FC298)
    static let sage500  = Color(hex: 0x5FAA7E)
    static let sage600  = Color(hex: 0x4A8E66)

    static let butter50  = Color(hex: 0xFFF9E5)
    static let butter100 = Color(hex: 0xFCF1D2)
    static let butter200 = Color(hex: 0xF8E2A6)
    static let butter400 = Color(hex: 0xF5C97B)
    static let butter500 = Color(hex: 0xE8B055)
    static let butter600 = Color(hex: 0xC9912E)

    static let blush100 = Color(hex: 0xFCE7E0)
    static let blush200 = Color(hex: 0xF8CFC0)
    static let blush400 = Color(hex: 0xF4A99B)
    static let blush500 = Color(hex: 0xE88C7B)

    static let ink100 = Color(hex: 0xF2EDE5)
    static let ink400 = Color(hex: 0x8C7B66)
    static let ink600 = Color(hex: 0x5C4F3E)
    static let ink800 = Color(hex: 0x2D2418)

    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

extension LinearGradient {
    static let appBackground = LinearGradient(
        colors: [Color.acorn50.opacity(0.7), .cream, Color.sage50.opacity(0.6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
