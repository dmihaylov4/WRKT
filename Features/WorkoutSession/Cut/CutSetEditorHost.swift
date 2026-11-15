//
//  CutSetEditorHost.swift
//  WRKT
//
//  RetrospectiveSetEditor's binding and unit behind the Cut set editor: every edit goes through
//  CutSetEditorLogic and back into the same entry binding the editors hand in.
//

import SwiftUI

struct CutSetEditorHost: View {
    @Binding var entry: WorkoutEntry

    @Environment(\.dismiss) private var dismiss
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    var body: some View {
        NavigationStack {
            CutSetEditorView(
                model: CutSetEditorLogic.model(entry, unit: unit),
                apply: { entry = CutSetEditorLogic.apply($0, to: entry, unit: unit) },
                done: { dismiss() }
            )
        }
    }
}
