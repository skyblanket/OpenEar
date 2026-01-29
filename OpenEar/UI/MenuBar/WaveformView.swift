import SwiftUI

/// Minimal waveform visualization for audio feedback
struct WaveformView: View {
    let level: Float

    // Number of bars in the waveform
    private let barCount = 20
    private let barSpacing: CGFloat = 3
    private let minBarHeight: CGFloat = 2
    private let cornerRadius: CGFloat = 1

    // Animation
    @State private var animatedLevels: [CGFloat] = []
    @State private var phase: Double = 0

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(barColor(for: index))
                        .frame(width: barWidth(in: geometry), height: barHeight(for: index, in: geometry))
                        .animation(.easeInOut(duration: 0.1), value: animatedLevels)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            initializeLevels()
            startAnimation()
        }
        .onChange(of: level) { _, newLevel in
            updateLevels(with: newLevel)
        }
    }

    // MARK: - Bar Calculations

    private func barWidth(in geometry: GeometryProxy) -> CGFloat {
        let totalSpacing = barSpacing * CGFloat(barCount - 1)
        return (geometry.size.width - totalSpacing) / CGFloat(barCount)
    }

    private func barHeight(for index: Int, in geometry: GeometryProxy) -> CGFloat {
        guard index < animatedLevels.count else { return minBarHeight }

        let level = animatedLevels[index]
        let maxHeight = geometry.size.height
        return max(minBarHeight, level * maxHeight)
    }

    private func barColor(for index: Int) -> Color {
        // Subtle gradient from center outward
        let center = barCount / 2
        let distance = abs(index - center)
        let opacity = 1.0 - (Double(distance) / Double(center)) * 0.3

        return Color.primary.opacity(opacity * 0.6)
    }

    // MARK: - Animation

    private func initializeLevels() {
        animatedLevels = Array(repeating: 0.1, count: barCount)
    }

    private func startAnimation() {
        // Continuous subtle animation for organic feel
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            phase += 0.1
            addNoise()
        }
    }

    private func updateLevels(with newLevel: Float) {
        let normalizedLevel = CGFloat(max(0, min(1, newLevel)))

        for i in 0..<barCount {
            // Create wave pattern emanating from center
            let center = barCount / 2
            let distance = abs(i - center)
            let delay = Double(distance) * 0.05

            // Base level with wave modulation
            let waveOffset = sin(phase - delay) * 0.2
            let targetLevel = normalizedLevel * (1.0 + waveOffset)

            // Smooth transition
            let currentLevel = animatedLevels[i]
            animatedLevels[i] = currentLevel + (targetLevel - currentLevel) * 0.3
        }
    }

    private func addNoise() {
        // Add subtle randomness for organic feel
        for i in 0..<animatedLevels.count {
            let noise = CGFloat.random(in: -0.02...0.02)
            animatedLevels[i] = max(0.05, min(1.0, animatedLevels[i] + noise))
        }
    }
}

// MARK: - Alternative: Simple Bar Visualization

struct SimpleWaveformView: View {
    let level: Float

    private let barCount = 5

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.5))
                    .frame(width: 4)
                    .scaleY(scaleFor(index: index))
                    .animation(.easeInOut(duration: 0.1), value: level)
            }
        }
    }

    private func scaleFor(index: Int) -> CGFloat {
        let normalizedLevel = CGFloat(max(0.1, min(1, level)))

        // Create a wave pattern
        let center = barCount / 2
        let distance = CGFloat(abs(index - center))
        let falloff = 1.0 - (distance / CGFloat(center)) * 0.5

        return normalizedLevel * falloff
    }
}

// MARK: - Scale Effect Extension

extension View {
    func scaleY(_ scale: CGFloat) -> some View {
        self.scaleEffect(CGSize(width: 1, height: scale), anchor: .center)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        WaveformView(level: 0.5)
            .frame(height: 40)
            .padding()

        SimpleWaveformView(level: 0.7)
            .frame(height: 30)
            .padding()
    }
    .frame(width: 280)
}
