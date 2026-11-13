//
//  CutTrainStatusBar.swift
//  WRKT
//
//  Dark status bar content while the Cut Train tab shows its lime field behind the status bar.
//
//  The app root sets .preferredColorScheme(.dark), and a status bar colour scheme set inside a
//  tab loses to it, so the Train view reports what it needs here and the shell applies it at
//  its root with the iOS 27 status bar toolbar placement. Earlier systems keep light content.
//  Only active under DS.Redesign.cutEnabled; otherwise the root modifier changes nothing.
//

import SwiftUI

/// What the visible Cut Train view asks of the status bar.
@Observable
@MainActor
final class CutTrainStatusBar {
    static let shared = CutTrainStatusBar()

    /// True while the lime field sits behind the status bar on screen.
    var wantsDarkContent = false
}

/// Applied once at the shell root. Dark content only while Train is the selected tab and its
/// view asks for it; nil (the app default) otherwise, so other tabs and the legacy path are
/// left alone and switching tabs restores the default at once.
struct CutTrainStatusBarRoot: ViewModifier {
    let trainSelected: Bool

    func body(content: Content) -> some View {
        if DS.Redesign.cutEnabled, #available(iOS 27, *) {
            content.toolbarColorScheme(
                trainSelected && CutTrainStatusBar.shared.wantsDarkContent ? .light : nil,
                for: .statusBar
            )
        } else {
            content
        }
    }
}

/// Applied by CutTrainView: reports the need while the view is on screen and withdraws it
/// when the view disappears (a pushed screen, another tab, the switch turned off).
struct CutTrainStatusBarReporter: ViewModifier {
    let darkContent: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { CutTrainStatusBar.shared.wantsDarkContent = darkContent }
            .onChange(of: darkContent) { _, value in CutTrainStatusBar.shared.wantsDarkContent = value }
            .onDisappear { CutTrainStatusBar.shared.wantsDarkContent = false }
    }
}
