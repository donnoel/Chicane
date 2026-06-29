import SwiftUI

struct PageHeader: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var tint: Color = .accentColor

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(tint.opacity(0.16))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(tint.opacity(0.34), lineWidth: 1)
                    )
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ChicaneTypography.screenTitle)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    Text(subtitle)
                        .font(ChicaneTypography.subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, systemImage == nil ? 0 : 2)
    }
}
