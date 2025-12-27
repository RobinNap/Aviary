//
//  LiveAircraft.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import CoreLocation

/// Represents a live aircraft with real-time position data from OpenSky Network
struct LiveAircraft: Identifiable, Equatable, Hashable {
    let id: String // icao24 transponder address
    let callsign: String?
    let originCountry: String
    let longitude: Double
    let latitude: Double
    let altitude: Double? // Barometric altitude in meters
    let onGround: Bool
    let velocity: Double? // Ground speed in m/s
    let heading: Double? // True track in degrees clockwise from north
    let verticalRate: Double? // Vertical rate in m/s
    let lastUpdate: Date
    
    /// CLLocationCoordinate2D for MapKit
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    /// Altitude in feet
    var altitudeInFeet: Int? {
        guard let alt = altitude else { return nil }
        return Int(alt * 3.28084)
    }
    
    /// Velocity in knots
    var velocityInKnots: Int? {
        guard let vel = velocity else { return nil }
        return Int(vel * 1.94384)
    }
    
    /// Display callsign or ID
    var displayName: String {
        callsign?.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? callsign!.trimmingCharacters(in: .whitespaces)
            : id.uppercased()
    }
    
    /// Rotation angle for display (MapKit uses radians, heading is in degrees)
    var rotationAngle: Double {
        (heading ?? 0) * .pi / 180
    }
}

// MARK: - Sample Data
extension LiveAircraft {
    static let sample = LiveAircraft(
        id: "a12345",
        callsign: "UAL123",
        originCountry: "United States",
        longitude: -118.4081,
        latitude: 33.9425,
        altitude: 3048, // ~10,000 feet
        onGround: false,
        velocity: 154, // ~300 knots
        heading: 270,
        verticalRate: -5.0,
        lastUpdate: Date()
    )
    
    static let sampleOnGround = LiveAircraft(
        id: "b67890",
        callsign: "DAL456",
        originCountry: "United States",
        longitude: -118.41,
        latitude: 33.94,
        altitude: 38,
        onGround: true,
        velocity: 0,
        heading: 90,
        verticalRate: 0,
        lastUpdate: Date()
    )
}

