import SwiftUI

extension Font {
    static func barlow(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .black: name = "BarlowSemiCondensed-Black"
        case .heavy: name = "BarlowSemiCondensed-ExtraBold"
        case .bold: name = "BarlowSemiCondensed-Bold"
        case .semibold: name = "BarlowSemiCondensed-SemiBold"
        case .medium: name = "BarlowSemiCondensed-Medium"
        case .light: name = "BarlowSemiCondensed-Light"
        default: name = "BarlowSemiCondensed-Regular"
        }
        return .custom(name, size: size)
    }
}
