//
//  Item.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
