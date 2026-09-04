import Combine
import SwiftUI

struct FocusStartRitualView: View {
    @Environment(\.dismiss) private var dismiss
    let durationMinutes: Int
    let onStart: (String) -> Void
    @State private var intention = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                Image(systemName: "scope")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("Choose your intention")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Give the next \(durationMinutes) minutes a purpose before distractions disappear.")
                    .foregroundStyle(.secondary)

                TextField("What will you focus on?", text: $intention, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)

                Button("Commit to This Session") {
                    onStart(intention.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .buttonStyle(NoxaPrimaryButtonStyle())
                .disabled(intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }
            .padding(24)
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct EndSessionRitualView: View {
    @Environment(\.dismiss) private var dismiss
    let onEnd: () -> Void
    @State private var secondsRemaining = 30
    @State private var reason = ""

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: CGFloat(30 - secondsRemaining) / 30)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(secondsRemaining)")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 160, height: 160)

                Text(secondsRemaining > 0 ? "Pause before you quit" : "Make an intentional choice")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(secondsRemaining > 0
                     ? "Breathe slowly. The option to end your session will appear after the pause."
                     : "If you still need to stop, briefly name the reason.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if secondsRemaining == 0 {
                    TextField("Why are you ending early?", text: $reason, axis: .vertical)
                        .lineLimit(2...3)
                        .textFieldStyle(.roundedBorder)

                    Button("End Session Early", role: .destructive) {
                        onEnd()
                        dismiss()
                    }
                    .buttonStyle(NoxaDestructiveButtonStyle())
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Button("Keep Focusing") { dismiss() }
                    .buttonStyle(NoxaPrimaryButtonStyle())
                Spacer()
            }
            .padding(24)
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .interactiveDismissDisabled(secondsRemaining > 0)
            .onReceive(timer) { _ in
                guard secondsRemaining > 0 else { return }
                secondsRemaining -= 1
            }
        }
    }
}

private struct NoxaDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(configuration.isPressed ? 0.65 : 0.85))
            .clipShape(RoundedRectangle(cornerRadius: 13))
    }
}
