//
//  Notifications.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 07.10.25.
//

import Foundation


extension Notification.Name {

    static let resetHomeToRoot = Notification.Name("resetHomeToRoot")
       static let openHomeRoot    = Notification.Name("openHomeRoot")
       static let homeTabReselected = Notification.Name("homeTabReselected")
       static let calendarTabReselected = Notification.Name("calendarTabReselected")
       static let cardioTabReselected = Notification.Name("cardioTabReselected")
       static let tabSelectionChanged = Notification.Name("tabSelectionChanged")
       static let tabDidChange = Notification.Name("tabDidChange")
       static let dismissLiveOverlay = Notification.Name("dismissLiveOverlay")
       static let rewardsDidSummarize = Notification.Name("rewardsDidSummarize")
}
