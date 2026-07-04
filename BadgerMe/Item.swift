//
//  Item.swift
//  BadgerMe
//
//  Created by Amos Glenn on 7/4/26.
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
