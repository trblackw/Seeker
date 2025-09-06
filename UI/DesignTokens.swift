//
//  DesignTokens.swift
//  Seeker
//
//  Linear-inspired design tokens for typography, colors, and shadows.
//

import AppKit

// MARK: - Spacing Scale

enum TZ { // 4pt base, tightened for terminal aesthetic
    static let x0: CGFloat = 0
    static let x1: CGFloat = 2
    static let x2: CGFloat = 4
    static let x3: CGFloat = 6
    static let x4: CGFloat = 8
    static let x5: CGFloat = 12
    static let x6: CGFloat = 16
    static let x8: CGFloat = 20
    static let x12: CGFloat = 28
    static let x16: CGFloat = 36
}

// MARK: - Typography

enum FontToken {
    static var ui: NSFont { monoFont(weight: .regular, size: 12) }
    static var uiMedium: NSFont { monoFont(weight: .medium, size: 12) }
    static var small: NSFont { monoFont(weight: .regular, size: 11) }
    static var title: NSFont { monoFont(weight: .semibold, size: 16) }

    private static func monoFont(weight: NSFont.Weight, size: CGFloat) -> NSFont {
        // Try SF Mono first, then fallback to system monospace
        if let f = NSFont(name: "SFMono-\(weightName(weight))", size: size) {
            return f
        }
        return .monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static func weightName(_ w: NSFont.Weight) -> String {
        switch w {
        case .medium: return "Medium"
        case .semibold: return "Semibold"
        case .bold: return "Bold"
        default: return "Regular"
        }
    }
}

// MARK: - Colors

enum ColorSchemeToken {
    // Terminal/Warp-inspired monochromatic palette
    static let bg       = NSColor(hex: "#0A0A0A")
    static let surface  = NSColor(hex: "#141414")
    static let elevated = NSColor(hex: "#1E1E1E")

    // Text - high contrast monochromatic
    static let textPrimary   = NSColor(hex: "#FFFFFF")
    static let textSecondary = NSColor(hex: "#808080")

    // Accent - subtle terminal green
    static let accent    = NSColor(hex: "#00FF41")
    static let separator = NSColor.white.withAlphaComponent(0.1)
    static let selectionFill = NSColor(hex: "#00FF41").withAlphaComponent(0.1)
}

// MARK: - Helpers

extension NSColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255
        let b = CGFloat(rgb & 0x0000FF) / 255

        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - NSView Styling

extension NSView {
    func applyCardBackground() {
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = ColorSchemeToken.surface.cgColor
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.4).cgColor
        layer?.shadowOpacity = 0.15
        layer?.shadowOffset = CGSize(width: 0, height: 1)
        layer?.shadowRadius = 3
    }

    func addHairlineSeparator(edge: NSRectEdge) {
        let sep = NSView(frame: .zero)
        sep.wantsLayer = true
        sep.layer?.backgroundColor = ColorSchemeToken.separator.cgColor
        addSubview(sep)
        sep.translatesAutoresizingMaskIntoConstraints = false
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        switch edge {
        case .minY:
            NSLayoutConstraint.activate([
                sep.heightAnchor.constraint(equalToConstant: 1.0 / scale),
                sep.leadingAnchor.constraint(equalTo: leadingAnchor),
                sep.trailingAnchor.constraint(equalTo: trailingAnchor),
                sep.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        case .maxY:
            NSLayoutConstraint.activate([
                sep.heightAnchor.constraint(equalToConstant: 1.0 / scale),
                sep.leadingAnchor.constraint(equalTo: leadingAnchor),
                sep.trailingAnchor.constraint(equalTo: trailingAnchor),
                sep.topAnchor.constraint(equalTo: topAnchor)
            ])
        case .minX:
            NSLayoutConstraint.activate([
                sep.widthAnchor.constraint(equalToConstant: 1.0 / scale),
                sep.topAnchor.constraint(equalTo: topAnchor),
                sep.bottomAnchor.constraint(equalTo: bottomAnchor),
                sep.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        case .maxX:
            NSLayoutConstraint.activate([
                sep.widthAnchor.constraint(equalToConstant: 1.0 / scale),
                sep.topAnchor.constraint(equalTo: topAnchor),
                sep.bottomAnchor.constraint(equalTo: bottomAnchor),
                sep.leadingAnchor.constraint(equalTo: leadingAnchor)
            ])
        @unknown default:
            break
        }
    }
}
