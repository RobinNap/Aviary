//
//  FlightCacheEntry.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import SwiftData

/// Cached flight data for an airport
@Model
final class FlightCacheEntry {
    var airportIcao: String
    var directionRaw: String
    var beginTimestamp: Date
    var endTimestamp: Date
    var fetchedAt: Date
    var flightsData: Data // JSON encoded [Flight]
    
    var direction: FlightDirection {
        get { FlightDirection(rawValue: directionRaw) ?? .arrival }
        set { directionRaw = newValue.rawValue }
    }
    
    /// Check if cache is still valid (within 5 minutes)
    var isValid: Bool {
        Date().timeIntervalSince(fetchedAt) < 300 // 5 minutes
    }
    
    init(
        airportIcao: String,
        direction: FlightDirection,
        beginTimestamp: Date,
        endTimestamp: Date,
        flightsData: Data
    ) {
        self.airportIcao = airportIcao
        self.directionRaw = direction.rawValue
        self.beginTimestamp = beginTimestamp
        self.endTimestamp = endTimestamp
        self.fetchedAt = Date()
        self.flightsData = flightsData
    }
    
    /// Decode cached flights
    func decodeFlights() -> [Flight] {
        (try? JSONDecoder().decode([Flight].self, from: flightsData)) ?? []
    }
}



