//
//  FilterComponents.swift
//  WRKT
//
//  Exercise filter UI components
//

import SwiftUI

// MARK: - Filters Bar

struct FiltersBar: View {
    @Binding var equip: EquipBucket
    @Binding var move:  MoveBucket
    var category: Binding<CategoryBucket>? = nil  // Optional for backward compatibility
    var coordinateSpace: CoordinateSpace = .global
    var onEquipmentFrameCaptured: ((CGRect) -> Void)? = nil
    var onMovementFrameCaptured: ((CGRect) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Category Row (if provided)
            if let categoryBinding = category {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CATEGORY")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(DS.Semantic.textSecondary.opacity(0.7))
                        .padding(.horizontal, 16)

                    ChipRow(all: CategoryBucket.allCases, selected: categoryBinding) { tapped in
                        categoryBinding.wrappedValue = (tapped == categoryBinding.wrappedValue ? .all : tapped)
                    } onClear: {
                        categoryBinding.wrappedValue = .all
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 10)

                // Subtle divider
                Rectangle()
                    .fill(DS.Semantic.border.opacity(0.3))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
            }

            // Equipment Row
            VStack(alignment: .leading, spacing: 6) {
                Text("EQUIPMENT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(DS.Semantic.textSecondary.opacity(0.7))
                    .padding(.horizontal, 16)

                ChipRow(all: EquipBucket.allCases, selected: $equip) { tapped in
                    equip = (tapped == equip ? .all : tapped)
                } onClear: {
                    equip = .all
                }
            }
            .padding(.top, category == nil ? 12 : 0)
            .padding(.bottom, 10)
            .captureFrame(in: coordinateSpace) { frame in
                onEquipmentFrameCaptured?(frame)
            }

            // Subtle divider
            Rectangle()
                .fill(DS.Semantic.border.opacity(0.3))
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            // Movement Row
            VStack(alignment: .leading, spacing: 6) {
                Text("MOVEMENT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(DS.Semantic.textSecondary.opacity(0.7))
                    .padding(.horizontal, 16)

                ChipRow(all: MoveBucket.allCases, selected: $move) { tapped in
                    move = (tapped == move ? .all : tapped)
                } onClear: {
                    move = .all
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 12)
            .captureFrame(in: coordinateSpace) { frame in
                onMovementFrameCaptured?(frame)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(DS.Semantic.surface)
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - Chip Row

struct ChipRow<T: CaseIterable & Hashable & RawRepresentable>: View where T.AllCases: RandomAccessCollection, T.RawValue == String {
    let all: T.AllCases
    @Binding var selected: T
    let onTap: (T) -> Void
    let onClear: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(all), id: \.self) { bucket in
                        SelectChip(
                            title: bucket.rawValue,
                            selected: bucket == selected,
                            tap: {
                                onTap(bucket)
                            },
                            clear: onClear
                        )
                        .id(bucket)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
            .onAppear {
                // Scroll to initial selection without animation
                proxy.scrollTo(selected, anchor: .center)
            }
            .onChange(of: selected) { _, newValue in
                // Smoothly scroll to newly selected chip
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Select Chip

struct SelectChip: View {
    let title: String
    let selected: Bool
    let tap: () -> Void
    let clear: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                tap()
            }
        }) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .medium))
                .foregroundStyle(selected ? DS.Palette.marone : DS.Semantic.textPrimary.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if selected {
                            Capsule()
                                .fill(DS.Palette.marone.opacity(0.15))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(DS.Palette.marone.opacity(0.5), lineWidth: 1.5)
                                )
                        } else {
                            Capsule()
                                .fill(DS.Semantic.surface50.opacity(0.3))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(DS.Semantic.border.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
        // Double-tap anywhere on the chip clears the current filter row
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    clear()
                }
            }
        )
        .onLongPressGesture(minimumDuration: 0.0, maximumDistance: 50) {
            // On release
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selected ? "Double tap to clear filter" : "Tap to select")
    }
}
