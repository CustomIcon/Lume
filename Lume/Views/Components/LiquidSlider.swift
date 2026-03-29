import SwiftUI

struct LiquidSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onEditingChanged: (Bool) -> Void = { _ in }

    // Internal drag state — completely separate from the bound value during drag
    @State private var isDragging = false
    @State private var dragRatio: CGFloat = 0
    @State private var capturedWidth: CGFloat = 0
    
    private let thumbRadius: CGFloat = 9
    private let trackHeight: CGFloat = 5

    private var rangeSpan: Double {
        range.upperBound - range.lowerBound
    }
    
    /// The ratio [0...1] used for visual positioning.
    /// During drag: uses the local drag ratio (immune to external value updates).
    /// Otherwise: derived from the bound value.
    private var displayRatio: CGFloat {
        if isDragging {
            return dragRatio
        }
        guard rangeSpan > 0 else { return 0 }
        return CGFloat(max(0, min(1, (value - range.lowerBound) / rangeSpan)))
    }

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let usableWidth = max(0, totalWidth - thumbRadius * 2)
            
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(.white.opacity(0.12))
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbRadius)
                
                // Progress Track
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white,
                                .white.opacity(0.8)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: displayRatio * usableWidth, height: trackHeight)
                    .padding(.leading, thumbRadius)
                    .shadow(color: .white.opacity(0.35), radius: 4)
                
                // Thumb
                Circle()
                    .fill(.white)
                    .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                    .scaleEffect(isDragging ? 1.2 : 1.0)
                    .shadow(color: .black.opacity(0.4), radius: isDragging ? 5 : 2, y: 1.5)
                    .overlay(
                        Circle()
                            .stroke(ThemeManager.shared.currentFlavor.accentColor.opacity(0.3), lineWidth: 0.5)
                    )
                    .offset(x: displayRatio * usableWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let currentUsable = max(0, geometry.size.width - thumbRadius * 2)
                        
                        if !isDragging {
                            isDragging = true
                            capturedWidth = geometry.size.width
                            onEditingChanged(true)
                        }
                        
                        guard currentUsable > 0 else { return }
                        
                        // Compute ratio from gesture position
                        let locationX = gesture.location.x - thumbRadius
                        let ratio = max(0, min(1, Double(locationX / currentUsable)))
                        dragRatio = ratio
                        
                        // Write the value back so time labels update
                        value = range.lowerBound + ratio * rangeSpan
                    }
                    .onEnded { _ in
                        // Compute final value from dragRatio (the source of truth during drag)
                        let finalValue = range.lowerBound + Double(dragRatio) * rangeSpan
                        value = finalValue
                        
                        // Signal editing ended (triggers seek)
                        onEditingChanged(false)
                        
                        // Clear drag state AFTER signaling, so the seek uses our final value
                        isDragging = false
                        dragRatio = 0
                    }
            )
        }
        .frame(height: 24)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
    }
}
