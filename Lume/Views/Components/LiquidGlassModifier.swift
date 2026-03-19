import SwiftUI

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var borderOpacity: Double
    var shadowRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(borderOpacity), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: shadowRadius, x: 0, y: shadowRadius / 2)
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 16, borderOpacity: Double = 0.15, shadowRadius: CGFloat = 10) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, borderOpacity: borderOpacity, shadowRadius: shadowRadius))
    }
    
    func liquidCard() -> some View {
        self.liquidGlass(cornerRadius: 16, borderOpacity: 0.2, shadowRadius: 12)
    }
    
    func liquidPanel() -> some View {
        self.liquidGlass(cornerRadius: 24, borderOpacity: 0.1, shadowRadius: 20)
    }
}
