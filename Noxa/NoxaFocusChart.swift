import SwiftUI

/// The Insights line chart: thin muted segments between softly glowing
/// points, drawn from real buckets on a zero baseline. Tap or drag to select
/// a point; the selected one brightens and its value shows above the plot.
struct NoxaFocusChart: View {
    let buckets: [FocusBucket]
    let label: (FocusBucket) -> String
    /// Short x-axis text under a point, or nil to leave it unlabeled.
    var axisLabel: (FocusBucket) -> String? = { _ in nil }
    @Binding var selection: FocusBucket?

    private let axisHeight: CGFloat = 22

    /// The scale starts at zero and tops out at the busiest bucket.
    private var maxMinutes: Int { max(buckets.map(\.minutes).max() ?? 0, 1) }
    private var isEmpty: Bool { buckets.allSatisfy { $0.minutes == 0 } }
    /// Dense ranges get smaller points so they don't merge into a band.
    private var pointSize: CGFloat { buckets.count > 12 ? 7 : 18 }

    var body: some View {
        GeometryReader { geometry in
            let plot = CGSize(width: geometry.size.width, height: geometry.size.height - axisHeight)
            let allPoints = positions(in: plot)
            // Future buckets keep their place on the axis but get no point
            // or line: they haven't happened, so they aren't zeros.
            let recorded = buckets.indices.filter { !buckets[$0].isFuture }
            let points = recorded.map { allPoints[$0] }
            let shown = recorded.map { buckets[$0] }
            ZStack {
                // A data-shaped fill under the line, fading to nothing.
                if !isEmpty, let first = points.first, let last = points.last {
                    let baseline = plot.height - pointSize * 1.6
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: baseline))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: last.x, y: baseline))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [NoxaTheme.accent.opacity(0.16), NoxaTheme.accent.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                }

                ForEach(Array(zip(buckets, allPoints)), id: \.0.id) { bucket, point in
                    if let text = axisLabel(bucket) {
                        Text(text)
                            .font(NoxaType.caption)
                            .foregroundStyle(
                                selection?.id == bucket.id
                                    ? NoxaTheme.primaryText
                                    : NoxaTheme.tertiaryText.opacity(bucket.isFuture ? 0.45 : 1)
                            )
                            .fixedSize()
                            .position(x: point.x, y: plot.height + axisHeight / 2 + 2)
                    }
                }

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(NoxaTheme.accentMuted.opacity(isEmpty ? 0.3 : 0.75), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                if !isEmpty {
                    ForEach(Array(zip(shown, points)), id: \.0.id) { bucket, point in
                        let isSelected = selection?.id == bucket.id
                        let isPeak = bucket.minutes == maxMinutes
                        let size = pointSize * (isSelected || isPeak ? 1.4 : (bucket.minutes == 0 ? 0.6 : 1))
                        ZStack {
                            // Empty buckets stay quiet; light marks real focus.
                            Circle()
                                .fill(NoxaTheme.accent.opacity(bucket.minutes == 0 ? 0 : (isSelected ? 0.22 : 0.12)))
                                .frame(width: size * 2, height: size * 2)
                            Circle()
                                .fill(isSelected || isPeak ? NoxaTheme.accentBright : NoxaTheme.accent.opacity(bucket.minutes == 0 ? 0.35 : 0.85))
                                .frame(width: size, height: size)
                                .shadow(color: NoxaTheme.accent.opacity(bucket.minutes == 0 ? 0 : (isSelected ? 0.6 : 0.3)), radius: isSelected ? 10 : 5)
                        }
                        .position(point)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isEmpty, !points.isEmpty else { return }
                        let nearest = points.indices.min { abs(points[$0].x - value.location.x) < abs(points[$1].x - value.location.x) }
                        if let nearest, selection?.id != shown[nearest].id {
                            NoxaHaptics.selection()
                            selection = shown[nearest]
                        }
                    }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus time chart")
        .accessibilityRepresentation {
            VStack {
                ForEach(buckets.filter { !$0.isFuture }) { bucket in
                    Text("\(label(bucket)), \(bucket.minutes) minutes, \(bucket.sessions) sessions")
                }
            }
        }
    }

    private func positions(in size: CGSize) -> [CGPoint] {
        guard !buckets.isEmpty else { return [] }
        let inset = pointSize * 1.6
        let width = size.width - inset * 2
        let height = size.height - inset * 2
        let step = buckets.count > 1 ? width / CGFloat(buckets.count - 1) : 0
        return buckets.enumerated().map { index, bucket in
            let ratio = CGFloat(bucket.minutes) / CGFloat(maxMinutes)
            return CGPoint(
                x: inset + step * CGFloat(index) + (buckets.count == 1 ? width / 2 : 0),
                y: inset + height * (1 - ratio)
            )
        }
    }
}
