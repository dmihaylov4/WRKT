//
//  CutRackPortalHooks.swift
//  WRKT
//
//  What the Home hex portal needs from the rack screen when it hosts it (nil everywhere else, so
//  the Me path is unchanged): its back button, the scene band's place on screen, and the scene
//  once it is built (the portal waits for its first frames before handing off from the still,
//  and takes its last frame as the next still).
//

import SwiftUI

struct CutRackPortalHooks {
    /// Replaces dismiss for the back button: the portal plays the way back first.
    var back: @MainActor () -> Void
    /// The scene band's frame in the portal's room space (CutRackPortalHooks.space: the cover's
    /// untransformed room layer), on layout changes only. Global coordinates would include the
    /// fly-through's transform and feed back into it.
    var sceneFrame: @MainActor (CGRect) -> Void
    /// The scene's make has built the room.
    var sceneBuilt: @MainActor (SceneState) -> Void
}

extension CutRackPortalHooks {
    static let space = "cutRackPortalRoom"
}

extension EnvironmentValues {
    @Entry var cutRackPortal: CutRackPortalHooks? = nil
}
