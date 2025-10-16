//
//  Notifications.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 07.10.25.
//

import Foundation


extension Notification.Name {
   
    static let tabSelectionChanged = Notification.Name("tabSelectionChanged")
    static let dismissLiveOverlay = Notification.Name("dismissLiveOverlay")
    static let openHomeRoot = Notification.Name("openHomeRoot")
    static let resetHomeToRoot = Notification.Name("resetHomeToRoot")
    static let homeTabReselected = Notification.Name("homeTabReselected")
    static let rewardsDidSummarize = Notification.Name("rewardsDidSummarize")
}
