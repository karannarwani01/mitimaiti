import SwiftUI

/// Animated gray placeholder used as a loading state.
/// Use as a base shape via `.skeleton()` modifier or directly as `SkeletonView()`.
struct SkeletonView: View {
    @Environment(\.adaptiveColors) private var colors
    @State private var phase: CGFloat = 0

    var cornerRadius: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            colors.surfaceMedium
                .overlay(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.5),
                            Color.white.opacity(0)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase)
                    .blendMode(.overlay)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .onAppear {
                    let span = geo.size.width + geo.size.width * 0.6
                    phase = -span / 2
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = span / 2
                    }
                }
        }
    }
}

extension View {
    /// Shows a `SkeletonView` overlay while `isLoading` is true.
    func skeleton(_ isLoading: Bool, cornerRadius: CGFloat = 8) -> some View {
        self.overlay(
            isLoading ? SkeletonView(cornerRadius: cornerRadius) : nil
        )
        .opacity(isLoading ? 0 : 1)
    }
}

/// Pre-baked skeleton for a Discover feed card.
struct DiscoverCardSkeleton: View {
    var body: some View {
        VStack(spacing: 12) {
            SkeletonView(cornerRadius: 24)
                .aspectRatio(0.72, contentMode: .fit)
            HStack(spacing: 8) {
                SkeletonView(cornerRadius: 6)
                    .frame(width: 140, height: 18)
                Spacer()
                SkeletonView(cornerRadius: 6)
                    .frame(width: 60, height: 18)
            }
        }
        .padding(.horizontal, 16)
    }
}
