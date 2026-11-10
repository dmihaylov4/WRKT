//
//  AppEvents.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 07.10.25.
//

import Foundation

extension Notification.Name {
    static let openLiveWorkoutTab = Notification.Name("WRKT.OpenLiveWorkoutTab")
    static let presentLiveWorkoutSheet = Notification.Name("WRKT.PresentLiveWorkoutSheet")
    static let plannedWorkoutDeleted = Notification.Name("WRKT.PlannedWorkoutDeleted")
    static let plannedWorkoutsChanged = Notification.Name("WRKT.PlannedWorkoutsChanged")
    static let appDependenciesDidConfigure = Notification.Name("WRKT.AppDependenciesDidConfigure")
    /// Fired when a post's comment count is corrected from real data.
    /// userInfo: ["postId": UUID, "count": Int]
    static let postCommentCountDidChange = Notification.Name("WRKT.PostCommentCountDidChange")
    /// Fired after battle scores are written to Supabase so the arena cards reload.
    static let battleScoresDidUpdate = Notification.Name("WRKT.BattleScoresDidUpdate")
    /// Fired from ProfileView to open the progress share sheet in FeedView.
    static let openProgressShareSheet = Notification.Name("WRKT.OpenProgressShareSheet")
}
