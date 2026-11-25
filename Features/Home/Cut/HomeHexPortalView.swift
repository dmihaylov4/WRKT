//
//  HomeHexPortalView.swift
//  WRKT
//
//  The hex portal's drawing: the cell on Home (a still of the room inside one of the room's
//  honeycomb cells, a white tube around it) and the cover that flies through it. Every moving part
//  of the fly-through is a render-time effect driven by one animatable progress value: the cell is
//  an animatable Shape (the mask and the tube), the room layer moves with a GeometryEffect (a layer
//  transform: the live RealityView keeps its size and is never laid out again per frame). Nothing
//  here reads a service; HomeHexPortalHost feeds it.
//

import SwiftUI
import UIKit

// MARK: - Shapes

/// A flat-topped hexagon filling the width of its rect, centred.
struct HexCellShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addLines(HomeHexGeometry.corners(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2))
        path.closeSubpath()
        return path
    }
}

/// What the fly-through's geometry is computed from, in the cover's coordinates.
struct HexPortalInputs: Equatable {
    var source: CGRect
    var scene: CGRect
    /// The cover's safe area (where the room lays out).
    var safe: CGSize
    /// The whole screen, in the same coordinates (extends past the safe area).
    var bounds: CGRect
}

/// The cell at a progress of the fly-through.
struct HexPortalShape: Shape {
    var progress: CGFloat
    let inputs: HexPortalInputs

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let frame = HomeHexGeometry.frame(progress: progress, source: inputs.source, scene: inputs.scene, bounds: inputs.bounds)
        var path = Path()
        path.addLines(HomeHexGeometry.corners(center: frame.center, radius: frame.radius))
        path.closeSubpath()
        return path
    }
}

/// Moves the room layer (live room, still, chrome cover) with the cell: x -> scale * x + offset.
/// A GeometryEffect is applied as a transform at render time: no body or layout per frame.
struct HexZoomEffect: GeometryEffect {
    var progress: CGFloat
    let inputs: HexPortalInputs

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let frame = HomeHexGeometry.frame(progress: progress, source: inputs.source, scene: inputs.scene, bounds: inputs.bounds)
        return ProjectionTransform(CGAffineTransform(a: frame.scale, b: 0, c: 0, d: frame.scale,
                                                     tx: frame.offset.x, ty: frame.offset.y))
    }
}

/// The room's light tube: a crisp white core with a tight halo (the owner turned down blurry
/// tubes in the room).
private struct HexTube<S: Shape>: View {
    let shape: S

    var body: some View {
        shape
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.4, lineJoin: .round))
            .shadow(color: .white.opacity(0.85), radius: 1.2)
            .shadow(color: .white.opacity(0.35), radius: 4)
    }
}

// MARK: - The window on Home

/// The still at rest, or the placeholder: a dark cell with the lime mark.
struct HexWindowFace: View {
    let image: UIImage?
    let sceneSize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(white: 0.05)
            if let image, sceneSize.width > 0 {
                let rect = HomeHexGeometry.restImageRect(sceneSize: sceneSize)
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .transition(.opacity)
            } else {
                VMarkShape()
                    .fill(DS.Cut.Colors.lime)
                    .frame(width: 26, height: 26 / VMarkShape.aspectRatio)
                    .frame(width: HomeHexGeometry.width, height: HomeHexGeometry.height)
                    .transition(.opacity)
            }
        }
        .frame(width: HomeHexGeometry.width, height: HomeHexGeometry.height, alignment: .topLeading)
        .clipShape(HexCellShape())
    }
}

/// The cell in the field's cut corner: one button.
struct HomeHexWindowView: View {
    let model: HomeHexPortalWindowModel
    let image: UIImage?
    let imageKey: String?
    let sceneSize: CGSize
    /// The cover has taken over (the window is drawn by the cover until it closes).
    let isHidden: Bool
    let focusToken: Int
    var pressChanged: (Bool) -> Void = { _ in }
    var open: () -> Void = {}

    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        Button(action: open) {
            ZStack {
                HexWindowFace(image: image, sceneSize: sceneSize)
                    .id(imageKey)
                HexTube(shape: HexCellShape())
            }
            .frame(width: HomeHexGeometry.width, height: HomeHexGeometry.height)
            .contentShape(HexCellShape())
        }
        .buttonStyle(HexPressStyle(pressChanged: pressChanged))
        .opacity(isHidden ? 0 : 1)
        .accessibilityLabel(Text(model.accessibilityLabel))
        .accessibilityValue(Text(model.accessibilityValue))
        .accessibilityHint(Text(model.accessibilityHint))
        .accessibilityFocused($focused)
        .onChange(of: focusToken) { _, _ in focused = true }
    }
}

/// Presses in slightly while held and reports touch-down and release (the room starts preparing
/// on touch-down).
private struct HexPressStyle: ButtonStyle {
    let pressChanged: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in pressChanged(pressed) }
    }
}

// MARK: - The cover

/// Everything over Home while the room is open from the window: a veil over Home, and the room
/// layer seen through the growing cell. The room layer is the live rack screen at full size, a
/// black cover over its controls with a hole for the scene band, and the still in that band.
struct HomeHexPortalOverlay<Room: View>: View {
    let coordinator: HomeHexPortalCoordinator
    @ViewBuilder let room: () -> Room

    var body: some View {
        GeometryReader { proxy in
            let global = proxy.frame(in: .global)
            let window = proxy.safeAreaInsets
            let inputs = HexPortalInputs(
                source: coordinator.sourceFrame.offsetBy(dx: -global.minX, dy: -global.minY),
                scene: coordinator.zoomScene,
                safe: proxy.size,
                bounds: CGRect(x: -window.leading, y: -window.top, width: proxy.size.width + window.leading + window.trailing,
                               height: proxy.size.height + window.top + window.bottom))
            ZStack(alignment: .topLeading) {
                Color.black
                    .opacity(coordinator.veilShown ? 1 : 0)
                    .frame(width: inputs.bounds.width, height: inputs.bounds.height)
                    .offset(x: inputs.bounds.minX, y: inputs.bounds.minY)
                    .accessibilityHidden(true)
                roomLayer(inputs)
                    .modifier(HexZoomEffect(progress: coordinator.progress, inputs: inputs))
                    .mask { HexPortalShape(progress: coordinator.progress, inputs: inputs) }
                HexTube(shape: HexPortalShape(progress: coordinator.progress, inputs: inputs))
                    .opacity(coordinator.tubeShown ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if coordinator.phase.isInteractive {
                    edgeSwipe(inputs)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .opacity(coordinator.coverOpacity)
        .onAppear { coordinator.coverAppeared() }
    }

    private func roomLayer(_ inputs: HexPortalInputs) -> some View {
        ZStack(alignment: .topLeading) {
            if coordinator.roomMounted {
                room()
                    .frame(width: inputs.safe.width, height: inputs.safe.height)
                    .coordinateSpace(.named(CutRackPortalHooks.space))
            }
            // The room's controls stay dark until the hand-off; the scene band shows through.
            Path { path in
                path.addRect(inputs.bounds)
                path.addRect(inputs.scene)
            }
            .fill(DS.Cut.Colors.background, style: FillStyle(eoFill: true))
            .opacity(1 - coordinator.controlsOpacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            still(inputs.scene)
                .opacity(coordinator.stillOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(width: inputs.safe.width, height: inputs.safe.height, alignment: .topLeading)
        .allowsHitTesting(coordinator.phase.isInteractive)
    }

    /// The still in the scene band: the small one (identical to the window on Home at the start),
    /// the full-resolution one faded over it early in the zoom. Without a still, the band is dark
    /// until the live scene arrives.
    private func still(_ scene: CGRect) -> some View {
        ZStack {
            DS.Cut.Colors.background
            if let rest = coordinator.restImage {
                stillImage(rest, scene)
            }
            if let full = coordinator.fullImage {
                stillImage(full, scene)
                    .opacity(coordinator.fullShown ? 1 : 0)
            }
        }
        .frame(width: scene.width, height: scene.height)
        .clipped()
        .offset(x: scene.minX, y: scene.minY)
    }

    private func stillImage(_ image: UIImage, _ scene: CGRect) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: scene.width, height: scene.height)
    }

    /// A swipe from the leading edge goes back, below the header (its back button stays tappable).
    private func edgeSwipe(_ inputs: HexPortalInputs) -> some View {
        Color.clear
            .frame(width: 16, height: max(0, inputs.safe.height - inputs.scene.minY))
            .contentShape(Rectangle())
            .offset(y: inputs.scene.minY)
            .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.width > 60, abs(value.translation.height) < value.translation.width {
                    coordinator.close()
                }
            })
            .accessibilityHidden(true)
    }
}
