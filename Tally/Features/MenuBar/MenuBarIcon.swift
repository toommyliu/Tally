import SwiftUI

struct MenuBarIcon: View {
    let count: Int
    let showsBadge: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "checklist")
                .symbolRenderingMode(.hierarchical)

            if showsBadge, count > 0 {
                Text(badgeTitle)
                    .font(.system(size: 8, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .frame(minWidth: 12, minHeight: 12)
                    .background(.red, in: Capsule())
                    .offset(x: 7, y: -6)
            }
        }
        .frame(width: 22, height: 18)
        .accessibilityLabel("Tally")
        .accessibilityValue(showsBadge ? "\(count) open reminders" : "")
    }

    private var badgeTitle: String {
        count > 99 ? "99+" : "\(count)"
    }
}
