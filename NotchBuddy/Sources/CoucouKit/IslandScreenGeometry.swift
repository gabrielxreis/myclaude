import Foundation

/// Resting island dimensions, using a physical notch only when the screen has one.
struct IslandScreenGeometry {
    static let fallbackNotchWidth: CGFloat = 184
    private static let noNotchWidth: CGFloat = 80
    private static let noNotchHeight: CGFloat = 24

    /// My Cloud, Settings → Geral → Tela: the island's size on a screen without a notch
    /// ("pequeno" keeps Coucou's 80×24 inside the menu bar; bigger ones hang a little below it).
    static var noNotchSize: (width: CGFloat, height: CGFloat, fitsMenuBar: Bool) {
        switch UserDefaults.standard.string(forKey: "cloudNoNotchSize") ?? "medio" {
        case "pequeno": return (noNotchWidth, noNotchHeight, true)
        case "grande":  return (150, 40, false)
        default:        return (116, 32, false)
        }
    }

    let hasNotch: Bool
    let width: CGFloat
    let height: CGFloat

    init(screenWidth: CGFloat, safeAreaTop: CGFloat,
         auxiliaryLeftWidth: CGFloat?, auxiliaryRightWidth: CGFloat?,
         menuBarHeight: CGFloat) {
        hasNotch = safeAreaTop > 0
        if hasNotch {
            if let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth {
                let measuredWidth = screenWidth - left - right
                width = measuredWidth > 0 && measuredWidth < screenWidth
                    ? measuredWidth : Self.fallbackNotchWidth
            } else {
                width = Self.fallbackNotchWidth
            }
            height = safeAreaTop
        } else {
            let size = Self.noNotchSize
            width = size.width
            height = size.fitsMenuBar ? min(size.height, menuBarHeight) : size.height
        }
    }
}

/// Shared by the compact view and the greeting's collapse destination.
struct IslandRestingLayout {
    let width: CGFloat
    let height: CGFloat
    /// The notch caps the character at 20 pt; without a notch the bigger sizes let it grow.
    var maxBot: CGFloat = 20

    var botDiameter: CGFloat { min(maxBot, max(0, height - 6)) }
    var botCenterY: CGFloat { height / 2 }
    var miniGridScale: CGFloat { min(1, max(0, height - 4) / 28) }
    var miniGridCenterX: CGFloat { width - 40 }
}
