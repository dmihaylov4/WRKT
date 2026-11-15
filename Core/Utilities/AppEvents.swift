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
    /// Fired after a post was deleted on the server from a screen other than the feed.
    /// userInfo: ["postId": UUID]
    static let postDidDelete = Notification.Name("WRKT.PostDidDelete")
    /// Fired after a post's caption or visibility was saved from a screen other than the feed.
    /// userInfo: ["postId": UUID, "visibility": String (PostVisibility raw value), "caption": String (absent when cleared)]
    static let postDidUpdate = Notification.Name("WRKT.PostDidUpdate")
    /// Fired after battle scores are written to Supabase so the arena cards reload.
    static let battleScoresDidUpdate = Notification.Name("WRKT.BattleScoresDidUpdate")
    /// Fired from ProfileView to open the progress share sheet in FeedView.
    static let openProgressShareSheet = Notification.Name("WRKT.OpenProgressShareSheet")
}
