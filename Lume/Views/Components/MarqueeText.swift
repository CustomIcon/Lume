import SwiftUI

struct MarqueeText: View {
    let text: String
    var font: Font = .body
    var fontWeight: Font.Weight = .regular
    var color: Color = .primary
    var speed: Double = 30
    var delay: Double = 3.0
    
    @State private var offset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            let shouldAnimate = contentWidth > geo.size.width
            
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(font)
                    .fontWeight(fontWeight)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(GeometryReader { textGeo in
                        Color.clear.onAppear { contentWidth = textGeo.size.width }
                    })
                    .offset(x: offset)
            }
            .disabled(true)
            .onAppear {
                containerWidth = geo.size.width
                if shouldAnimate { startAnimation() }
            }
            .onChange(of: text) {
                stopAnimation()
                if shouldAnimate { startAnimation() }
            }
        }
    }
    
    private func stopAnimation() {
        withAnimation(.none) { offset = 0 }
    }
    
    private func startAnimation() {
        withAnimation(.linear(duration: Double(contentWidth) / speed).delay(delay).repeatForever(autoreverses: false)) {
            offset = -contentWidth
        }
    }
}
