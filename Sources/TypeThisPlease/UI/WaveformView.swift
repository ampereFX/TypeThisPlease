import SwiftUI

struct WaveformView: View {
    let samples: [Double]
    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.05))

                Path { path in
                    let baseline = height / 2
                    guard !samples.isEmpty else {
                        path.move(to: CGPoint(x: 0, y: baseline))
                        path.addLine(to: CGPoint(x: width, y: baseline))
                        return
                    }

                    let step = width / CGFloat(max(samples.count - 1, 1))
                    path.move(to: CGPoint(x: 0, y: baseline))

                    for index in samples.indices {
                        let sample = CGFloat(samples[index])
                        let amplitude = sample * (height * 0.34)
                        let point = CGPoint(x: CGFloat(index) * step, y: baseline - amplitude)
                        path.addLine(to: point)
                    }

                    for index in samples.indices.reversed() {
                        let sample = CGFloat(samples[index])
                        let amplitude = sample * (height * 0.34)
                        let point = CGPoint(x: CGFloat(index) * step, y: baseline + amplitude)
                        path.addLine(to: point)
                    }

                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(isActive ? 0.38 : 0.14),
                            Color.white.opacity(isActive ? 0.18 : 0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { path in
                    let baseline = height / 2
                    let step = width / CGFloat(max(samples.count - 1, 1))
                    path.move(to: CGPoint(x: 0, y: baseline))

                    for index in samples.indices {
                        let sample = CGFloat(samples[index])
                        let amplitude = sample * (height * 0.34)
                        path.addLine(to: CGPoint(x: CGFloat(index) * step, y: baseline - amplitude))
                    }
                }
                .stroke(Color.white.opacity(isActive ? 0.82 : 0.34), lineWidth: 1.4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}
