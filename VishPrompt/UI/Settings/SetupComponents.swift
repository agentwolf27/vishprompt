import SwiftUI

// Building blocks shared by Setup and Settings, so the two read the same.

@MainActor
func sectionTitle(_ title: String, badge: String?) -> some View {
    HStack {
        Text(title).font(.headline)
        Spacer()
        if let badge {
            Text(badge)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.15), in: Capsule())
                .foregroundStyle(.green)
        }
    }
}

@MainActor
func calloutRow(
    icon: String,
    tint: Color,
    text: String,
    button: String,
    action: @escaping () -> Void
) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Image(systemName: icon).foregroundStyle(tint)
        Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        Button(button, action: action).font(.caption)
    }
    .padding(12)
    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
}
