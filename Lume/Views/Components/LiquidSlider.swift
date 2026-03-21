import SwiftUI

struct LiquidSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(height: 4)
                
                // Progress Track
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [ThemeManager.shared.currentFlavor.accentColor, ThemeManager.shared.currentFlavor.accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * geometry.size.width), height: 4)
                
                // Thumb
                Circle()
                    .fill(.white)
                    .frame(width: isDragging ? 14 : 10, height: isDragging ? 14 : 10)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .overlay(
                        Circle()
                            .stroke(ThemeManager.shared.currentFlavor.accentColor.opacity(0.5), lineWidth: 1)
                    )
                    .offset(x: CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * geometry.size.width - (isDragging ? 7 : 5))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let newValue = range.lowerBound + Double(gesture.location.x / geometry.size.width) * (range.upperBound - range.lowerBound)
                        value = min(max(range.lowerBound, newValue), range.upperBound)
                        onEditingChanged(true)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 20)
    }
}
