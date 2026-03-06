import SwiftUI

struct MicrophoneLevelMeterView: View {
    let level: Double
    let isActive: Bool

    private let barCount = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(fillColor(for: index))
                        .frame(maxWidth: .infinity)
                        .frame(height: CGFloat(10 + index * 2))
                        .opacity(isFilled(index) ? 1 : 0.18)
                        .animation(.easeOut(duration: 0.12), value: level)
                }
            }
            .frame(height: 42)

            HStack {
                Text(isActive ? "Listening…" : "Idle")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(level * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func isFilled(_ index: Int) -> Bool {
        let threshold = Double(index + 1) / Double(barCount)
        return level >= threshold
    }

    private func fillColor(for index: Int) -> Color {
        let progress = Double(index) / Double(max(1, barCount - 1))
        if progress < 0.55 {
            return Color.green
        }
        if progress < 0.8 {
            return Color.yellow
        }
        return Color.red
    }
}
