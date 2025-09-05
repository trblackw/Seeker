//
//  DesignTokens.swift
//  Seeker
//
//  Linear-inspired design tokens for typography, colors, and shadows.
//

import AppKit

// MARK: - Spacing Scale

enum TZ { // 8pt base, like Linear
    static let x0: CGFloat = 0
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    static let x5: CGFloat = 20
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32
    static let x12: CGFloat = 48
    static let x16: CGFloat = 64
}

// MARK: - Typography

enum FontToken {
    static var ui: NSFont { interFont(weight: .regular, size: 13) }
    static var uiMedium: NSFont { interFont(weight: .medium, size: 13) }
    static var small: NSFont { interFont(weight: .regular, size: 12) }
    static var title: NSFont { interFont(weight: .semibold, size: 20) }

    private static func interFont(weight: NSFont.Weight, size: CGFloat) -> NSFont {
        if let f = NSFont(name: "Inter-\(weightName(weight))", size: size) {
            return f
        }
        return .systemFont(ofSize: size, weight: weight)
    }

    private static func weightName(_ w: NSFont.Weight) -> String {
        switch w {
        case .medium: return "Medium"
        case .semibold: return "SemiBold"
        case .bold: return "Bold"
        default: return "Regular"
        }
    }
}

// MARK: - Colors

enum ColorSchemeToken {
    // Linear-inspired charcoal palette
    static let bg       = NSColor(hex: "#1C1C1E")
    static let surface  = NSColor(hex: "#2C2C2E")
    static let elevated = NSColor(hex: "#3A3A3C")

    // Text
    static let textPrimary   = NSColor.white.withAlphaComponent(0.92)
    static let textSecondary = NSColor.white.withAlphaComponent(0.56)

    // Accent
    static let accent    = NSColor(hex: "#9E7AFF")
    static let separator = NSColor.white.withAlphaComponent(0.08)
    static let selectionFill = NSColor.white.withAlphaComponent(0.06)
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
        layer?.cornerRadius = 8
        layer?.backgroundColor = ColorSchemeToken.surface.cgColor
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.25).cgColor
        layer?.shadowOpacity = 0.08
        layer?.shadowOffset = CGSize(width: 0, height: 1)
        layer?.shadowRadius = 6
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
