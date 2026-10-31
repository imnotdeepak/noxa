import SwiftUI

struct UpdateRequiredView: View {
    @EnvironmentObject private var releasePolicy: ReleasePolicyService

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()

            Image(systemName: "arrow.down.app")
                .font(.system(size: 42))
                .foregroundStyle(NoxaTheme.accent)

            Text("Update Noxa to continue")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("This version can no longer safely use the latest Noxa data. Existing Focus, schedule, and daily-limit blocks still release at their saved times.")
                .foregroundStyle(NoxaTheme.secondaryText)

            Link("Open App Store", destination: ReleasePolicyService.appStoreURL)
                .buttonStyle(NoxaPrimaryButtonStyle())

            Button("Check again") {
                Task { await releasePolicy.refresh(force: true) }
            }
            .buttonStyle(NoxaSecondaryButtonStyle())

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(NoxaTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
