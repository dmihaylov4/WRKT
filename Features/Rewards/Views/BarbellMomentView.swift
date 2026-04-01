// Features/Rewards/Views/BarbellMomentView.swift
import SwiftUI
import RealityKit
import SwiftData

// Minimal scene state for the moment view animation.
private struct BarbellMomentSceneState {
    var rotAngle: Float = 0
    var lastTime: Double = 0
    var root: Entity? = nil
    var needsRebuild = true
}

/// WinScreen Page 2: plates animate onto the bar one by one.
/// Shown only when earnedPlates is non-empty.
struct BarbellMomentView: View {
    let plates: [EarnedPlateInfo]
    let onDismiss: () -> Void

    // Previously racked plates (the existing barbell state shown as the base)
    @Query(filter: #Predicate<EarnedPlate> { $0.isRacked == true })
    private var previouslyRackedPlates: [EarnedPlate]

    // Note: newly earned plates arrive via the `plates` prop, NOT via @Query.
    // They have isRacked == false at this point. The scene renders the existing barbell
    // state from @Query as the base, then the animation layer adds the new plates
    // from the prop one by one (purely visual: no SwiftData read for the new plates).
    @State private var seatedCount = 0
    @State private var scene = BarbellMomentSceneState()
    @State private var isDragging = false
    @State private var lastTranslationX: CGFloat = 0
    @State private var showDoneButton = false
    @State private var animationTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Title
                VStack(spacing: 6) {
                    Text("Added to your Barbell")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(plates.count) new plate\(plates.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.top, 48)
                .padding(.bottom, 24)

                // Barbell scene
                ZStack {
                    Color.black
                    TimelineView(.animation) { _ in
                        RealityView { _ in
                            // Stub: real scene setup wired in Task 8 when BarbellPreviewView is refactored.
                        } update: { _ in
                            // Stub: wired in Task 8
                            // No auto-spin: static by default
                        }
                        .gesture(
                            DragGesture()
                                .targetedToAnyEntity()
                                .onChanged { value in
                                    isDragging = true
                                    let delta = Float(value.translation.width - lastTranslationX) * 0.008
                                    scene.rotAngle -= delta
                                    scene.root?.orientation = simd_quatf(angle: scene.rotAngle, axis: SIMD3(0, 1, 0))
                                    lastTranslationX = value.translation.width
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    lastTranslationX = 0
                                }
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 280)

                Spacer()

                // Done button
                if showDoneButton {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .background(DS.Semantic.brand)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            animationTask = startPlateAnimation()
        }
        .onDisappear {
            animationTask?.cancel()
        }
    }

    // MARK: - Animation sequence

    @discardableResult
    private func startPlateAnimation() -> Task<Void, Never> {
        Task { @MainActor in
            for index in plates.indices {
                try? await Task.sleep(for: .seconds(Double(index) * 0.6 + 0.3))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    seatedCount = index + 1
                }
                BarbellProgressService.shared.playClinkHaptic()
            }
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showDoneButton = true
            }
        }
    }

}
