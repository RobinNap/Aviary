//
//  Item.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
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
