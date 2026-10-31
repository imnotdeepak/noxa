import SwiftUI

/// Noxa's signature ring. Ready, it is a full quiet ring so it never looks
/// like a session already running; during a session the lime arc shows time
/// elapsed, muted until Screen Time confirms the block.
struct NoxaFocusHalo: View {
    let progress: Double
    let value: String
    let caption: String
    var diameter: CGFloat = 260
    var lineWidth: CGFloat = 7
    /// During a session the ring advances once a second; a one-second linear
    /// ease between ticks makes it sweep steadily instead of stepping.
    var isCountingDown = false
    var style: Style = .progress

    enum Style {
        /// Ready to start: a complete, dim ring that measures nothing.
        case ready
        /// Started but not yet confirmed by Screen Time.
        case pending
        /// Confirmed and counting.
        case progress
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(NoxaTheme.elevated, lineWidth: lineWidth)

            if style == .ready {
                Circle()
                    .stroke(NoxaTheme.accentMuted.opacity(0.45), lineWidth: lineWidth)
            } else {
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(
                        style == .pending
                            ? AnyShapeStyle(NoxaTheme.accentMuted.opacity(0.6))
                            : AnyShapeStyle(AngularGradient(
                                colors: [NoxaTheme.accentMuted, NoxaTheme.accent, NoxaTheme.accentBright],
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360 * max(progress, 0.01))
                            )),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: NoxaTheme.accent.opacity(style == .pending ? 0 : 0.35), radius: 8)
                    .noxaAnimation(isCountingDown ? .linear(duration: 1) : NoxaMotion.spring, value: progress)
            }

            VStack(spacing: 10) {
                Text(value)
                    .font(.system(size: 60, weight: .medium).monospacedDigit())
                    .tracking(-1.8)
                    .foregroundStyle(NoxaTheme.primaryText)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(caption)
                    .font(NoxaType.footnoteMedium)
                    .tracking(2.4)
                    .foregroundStyle(NoxaTheme.secondaryText)
            }
            .padding(.horizontal, lineWidth + 24)
        }
        .frame(width: diameter, height: diameter)
        .background {
            // Dark olive depth inside the ring; the ambient motion lives in
            // the screen frame, not here.
            Circle()
                .fill(RadialGradient(
                    colors: [NoxaTheme.olive.opacity(0.35), NoxaTheme.background.opacity(0.2)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                ))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value), \(caption.lowercased())")
    }
}
