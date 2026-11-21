//
//  CutChooseNameHost.swift
//  WRKT
//
//  Wires the Cut Choose your name screen to the shared controller: save through the auth service,
//  sign out through it, success and error haptics. It never dismisses itself: once the profile has
//  a real name, SocialNameGate shows what was behind the step.
//

import SwiftUI

struct CutChooseNameHost: View {
    @State private var controller: ChooseNameController
    private let close: (() -> Void)?

    init(controller: ChooseNameController, close: (() -> Void)? = nil) {
        _controller = State(initialValue: controller)
        self.close = close
    }

    var body: some View {
        @Bindable var controller = controller
        CutChooseNameView(
            model: controller.model,
            form: $controller.form,
            actions: ChooseNameActions(
                close: close,
                save: { Task { await save() } },
                signOut: { Task { await controller.signOut() } }
            )
        )
    }

    private func save() async {
        if await controller.submit() {
            Haptics.success()
        } else if controller.failure != nil {
            Haptics.error()
        }
    }
}
