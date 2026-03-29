import SwiftUI

@available(macOS 26.0, *)
struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

@available(macOS 26.0, *)
extension View {

    func liquidGlass(cornerRadius: CGFloat = 16) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }

    func liquidCard() -> some View {
        self.liquidGlass(cornerRadius: 16)
    }

    func liquidPanel() -> some View {
        self.liquidGlass(cornerRadius: 24)
    }
}
