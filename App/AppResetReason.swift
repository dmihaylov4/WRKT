//
//  AppResetReason.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 18.10.25.
//


import Foundation

enum AppResetReason: String {
    case user_intent       // explicit user action (e.g., “Start Strength Workout”)
    case debug
}

enum AppBus {
    static func postResetHome(reason: AppResetReason,
                              file: String = #fileID,
                              line: Int = #line) {
        print("📣 postResetHome(reason=\(reason.rawValue)) @\(file):\(line)")
        NotificationCenter.default.post(
            name: .resetHomeToRoot,
            object: reason.rawValue,
            userInfo: ["reason": reason.rawValue]
        )
    }
}
