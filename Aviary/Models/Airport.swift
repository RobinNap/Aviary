//
//  Airport.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation

/// Represents an airport with essential identification and location data
struct Airport: Identifiable, Codable, Hashable {
    let id: String // ICAO code as unique identifier
    let icao: String
    let iata: String?
    let name: String
    let city: String?
    let country: String?
    let latitude: Double
    let longitude: Double
    let elevation: Int? // in feet
    let timezone: String?
    
    init(
        icao: String,
        iata: String? = nil,
        name: String,
        city: String? = nil,
        country: String? = nil,
        latitude: Double,
        longitude: Double,
        elevation: Int? = nil,
        timezone: String? = nil
    ) {
        self.id = icao
        self.icao = icao
        self.iata = iata
        self.name = name
        self.city = city
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.timezone = timezone
    }
    
    /// Display name combining city and airport name
    var displayName: String {
        if let city = city, !city.isEmpty {
            return "\(city) - \(name)"
        }
        return name
    }
    
    /// Short code display (IATA preferred, fallback to ICAO)
    var shortCode: String {
        iata ?? icao
    }
    
    /// Full code display showing both codes
    var fullCode: String {
        if let iata = iata {
            return "\(iata)/\(icao)"
        }
        return icao
    }
}

// MARK: - Sample Data for Previews
extension Airport {
    static let sampleLAX = Airport(
        icao: "KLAX",
        iata: "LAX",
        name: "Los Angeles International Airport",
        city: "Los Angeles",
        country: "United States",
        latitude: 33.9425,
        longitude: -118.4081,
        elevation: 125,
        timezone: "America/Los_Angeles"
    )
    
    static let sampleJFK = Airport(
        icao: "KJFK",
        iata: "JFK",
        name: "John F. Kennedy International Airport",
        city: "New York",
        country: "United States",
        latitude: 40.6413,
        longitude: -73.7781,
        elevation: 13,
        timezone: "America/New_York"
    )
    
    static let sampleLHR = Airport(
        icao: "EGLL",
        iata: "LHR",
        name: "Heathrow Airport",
        city: "London",
        country: "United Kingdom",
        latitude: 51.4700,
        longitude: -0.4543,
        elevation: 83,
        timezone: "Europe/London"
    )
    
    static let sampleAMS = Airport(
        icao: "EHAM",
        iata: "AMS",
        name: "Amsterdam Airport Schiphol",
        city: "Amsterdam",
        country: "Netherlands",
        latitude: 52.3086,
        longitude: 4.7639,
        elevation: -11,
        timezone: "Europe/Amsterdam"
    )
    
    static let samples: [Airport] = [sampleLAX, sampleJFK, sampleLHR, sampleAMS]
}


