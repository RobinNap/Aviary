//
//  RecentAirport.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import SwiftData

/// Persisted recently visited airport
@Model
final class RecentAirport {
    var icao: String
    var iata: String?
    var name: String
    var city: String?
    var country: String?
    var latitude: Double
    var longitude: Double
    var visitedAt: Date
    
    init(
        icao: String,
        iata: String? = nil,
        name: String,
        city: String? = nil,
        country: String? = nil,
        latitude: Double,
        longitude: Double,
        visitedAt: Date = Date()
    ) {
        self.icao = icao
        self.iata = iata
        self.name = name
        self.city = city
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.visitedAt = visitedAt
    }
    
    /// Convert to Airport model
    func toAirport() -> Airport {
        Airport(
            icao: icao,
            iata: iata,
            name: name,
            city: city,
            country: country,
            latitude: latitude,
            longitude: longitude
        )
    }
}

