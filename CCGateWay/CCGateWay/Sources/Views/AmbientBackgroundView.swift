import SwiftUI

struct AmbientBackgroundView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            // Base dark background
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            // Orb 1: Cool Slate
            Circle()
                .fill(Color(hue: 0.6, saturation: 0.15, brightness: 0.25).opacity(0.6))
                .frame(width: 500, height: 500)
                .offset(x: animate ? -200 : 200, y: animate ? -100 : 100)
                .blur(radius: 120)

            // Orb 2: Muted Blue-Gray
            Circle()
                .fill(Color(hue: 0.58, saturation: 0.12, brightness: 0.3).opacity(0.5))
                .frame(width: 400, height: 400)
                .offset(x: animate ? 200 : -200, y: animate ? 150 : -100)
                .blur(radius: 100)

            // Orb 3: Subtle Steel
            Circle()
                .fill(Color(hue: 0.63, saturation: 0.1, brightness: 0.2).opacity(0.5))
                .frame(width: 300, height: 300)
                .offset(x: animate ? -100 : 150, y: animate ? 200 : -200)
                .blur(radius: 120)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 10.0).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

#Preview {
    AmbientBackgroundView()
}
