import SwiftUI

struct LegalLinksView: View {
    private static let privacyURL = URL(string: "https://noxaapp.com/privacy")!
    private static let termsURL = URL(string: "https://noxaapp.com/terms")!

    var body: some View {
        HStack(spacing: 12) {
            Link("Privacy Policy", destination: Self.privacyURL)
            Text("·")
                .accessibilityHidden(true)
            Link("Terms of Use", destination: Self.termsURL)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}
