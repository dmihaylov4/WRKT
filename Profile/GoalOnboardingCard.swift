import SwiftUI


struct GoalOnboardingCard: View {
    let onSet: () -> Void

    init(onSet: @escaping () -> Void = {}) {
        self.onSet = onSet
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Set your weekly goal")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Customize your fitness targets and track progress")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)
                .foregroundStyle(Color(hex: "#F4E409"))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex:"#232323"), Color(hex:"#353535")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1))
        )
        .foregroundStyle(.white)
    }
}

private extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >>  8) & 0xFF) / 255.0
        let b = Double( v        & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
