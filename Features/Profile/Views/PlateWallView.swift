// Features/Profile/Views/PlateWallView.swift
import SwiftUI
import SwiftData

struct PlateWallView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<EarnedPlate> { $0.isRacked == true })
    private var rackedPlates: [EarnedPlate]
    @Query(filter: #Predicate<EarnedPlate> { $0.earnedByEvent != "starter" })
    private var ownedPlates: [EarnedPlate]

    // Drag state
    @State private var draggedPlate: EarnedPlate? = nil
    @State private var dragLocation: CGPoint = .zero
    @State private var barbellFrame: CGRect = .zero
    @State private var dropSide: DropSide? = nil

    enum DropSide { case left, right }

    private var totalWeight: Double {
        let racked = rackedPlates.filter { $0.earnedByEvent != "starter" }
        return 20 + racked.reduce(0) { $0 + $1.weightKg } * 2
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Navigation bar
                HStack {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DS.Semantic.brand)
                    Spacer()
                    Text("Your Barbell")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    // Balance invisible button
                    Text("Done").opacity(0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // --- Top zone: Barbell ---
                ZStack {
                    Color.black
                    BarbellPreviewView(mode: .editor)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { barbellFrame = geo.frame(in: .global) }
                                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                        barbellFrame = newFrame
                                    }
                            }
                        )

                    // Drop zone highlights
                    if draggedPlate != nil {
                        HStack(spacing: 0) {
                            Color.white.opacity(dropSide == .left ? 0.06 : 0.02)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            Color.white.opacity(dropSide == .right ? 0.06 : 0.02)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.15), value: dropSide)
                    }
                }
                .frame(height: 280)

                // Total weight
                Text("Bar 20kg + \(Int(totalWeight - 20))kg = \(Int(totalWeight))kg total")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.vertical, 8)

                Divider()
                    .background(DS.Semantic.border)

                // --- Bottom zone: Plate Wall ---
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(plateTierSections(), id: \.tierID) { section in
                            PlateShelfRow(
                                tierName: section.tierName,
                                plates: section.plates,
                                onDragStart: { plate, location in
                                    draggedPlate = plate
                                    dragLocation = location
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }

            // Floating drag ghost
            if let dragged = draggedPlate {
                PlateCell(plate: dragged, isLifted: true)
                    .position(dragLocation)
                    .allowsHitTesting(false)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    guard draggedPlate != nil else { return }
                    dragLocation = value.location
                    updateDropSide(at: value.location)
                }
                .onEnded { value in
                    commitDrop(at: value.location)
                    draggedPlate = nil
                    dropSide = nil
                }
        )
    }

    // MARK: - Sections

    private struct TierSection {
        let tierID: Int
        let tierName: String
        let plates: [EarnedPlate]
    }

    private func plateTierSections() -> [TierSection] {
        let names = [0: "Raw Iron", 1: "Cast Iron", 2: "Black Bumper",
                     3: "Brass", 4: "Competition", 5: "Polished Steel", 6: "Gold"]
        return (0...6).reversed().compactMap { id in
            let plates = ownedPlates.filter { $0.tierID == id }
            guard !plates.isEmpty else { return nil }
            return TierSection(tierID: id, tierName: names[id] ?? "Plate", plates: plates)
        }
    }

    // MARK: - Drop logic

    private func updateDropSide(at point: CGPoint) {
        let midX = barbellFrame.midX
        dropSide = point.x < midX ? .left : .right
    }

    private func commitDrop(at point: CGPoint) {
        guard let plate = draggedPlate else { return }
        guard barbellFrame.contains(point) else { return }
        // rackPlate fills the next available slot 0-3; bilateral rendering handles both sides.
        try? BarbellProgressService.shared.rackPlate(plate)
    }
}

// MARK: - PlateShelfRow

private struct PlateShelfRow: View {
    let tierName: String
    let plates: [EarnedPlate]
    let onDragStart: (EarnedPlate, CGPoint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Shelf label
            Text(tierName.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 12)

            // Shelf line + plates
            ZStack(alignment: .leading) {
                // Shelf line
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)
                    .padding(.top, 24)

                // Plates
                HStack(spacing: 10) {
                    ForEach(plates) { plate in
                        if plate.isRacked {
                            PlateCell(plate: plate, isLifted: false)
                                .opacity(0.25)
                                .overlay(
                                    // Museum plaque
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                                        .overlay(
                                            Text(plate.weightKg > 0 ? "\(Int(plate.weightKg))kg" : "")
                                                .font(.system(size: 7, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.4))
                                        )
                                )
                        } else {
                            PlateCell(plate: plate, isLifted: false)
                                .gesture(
                                    DragGesture(minimumDistance: 4, coordinateSpace: .global)
                                        .onChanged { value in
                                            onDragStart(plate, value.location)
                                        }
                                )
                        }
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }
}

// MARK: - PlateCell

private struct PlateCell: View {
    let plate: EarnedPlate
    let isLifted: Bool

    private var color: Color {
        switch plate.tierID {
        case 0: return Color(red: 0.40, green: 0.18, blue: 0.07)
        case 1: return Color(red: 0.14, green: 0.14, blue: 0.14)
        case 2: return Color(red: 0.07, green: 0.07, blue: 0.07)
        case 3: return Color(red: 0.75, green: 0.60, blue: 0.25)
        case 4: return Color(red: 0.82, green: 0.09, blue: 0.09)
        case 5: return Color(red: 0.72, green: 0.76, blue: 0.80)
        case 6: return Color(red: 0.88, green: 0.68, blue: 0.12)
        case 7: return Color(red: 0.2, green: 0.7, blue: 0.3)   // starter: bright green
        default: return .gray
        }
    }

    private var textColor: Color {
        [0, 1, 2].contains(plate.tierID) ? .white : .black
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 44, height: 44)
            .overlay(
                Text(plate.weightKg > 0 ? "\(Int(plate.weightKg))" : "")
                    .font(.caption.weight(.black))
                    .foregroundStyle(textColor)
            )
            .scaleEffect(isLifted ? 1.15 : 1.0)
            .shadow(color: isLifted ? color.opacity(0.5) : .clear, radius: isLifted ? 8 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isLifted)
    }
}
