//
//  FavoriteAirport.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import SwiftData

/// Persisted favorite airport for quick access
@Model
final class FavoriteAirport {
    var icao: String
    var iata: String?
    var name: String
    var city: String?
    var country: String?
    var latitude: Double
    var longitude: Double
    var addedAt: Date
    
    init(
        icao: String,
        iata: String? = nil,
        name: String,
        city: String? = nil,
        country: String? = nil,
        latitude: Double,
        longitude: Double,
        addedAt: Date = Date()
    ) {
        self.icao = icao
        self.iata = iata
        self.name = name
        self.city = city
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.addedAt = addedAt
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

