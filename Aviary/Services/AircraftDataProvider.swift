//
//  AircraftDataProvider.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import CoreLocation

/// Protocol for aircraft data providers
protocol AircraftDataProvider {
    /// Name of the provider
    var name: String { get }
    
    /// Whether this provider requires authentication
    var requiresAuth: Bool { get }
    
    /// Whether authentication is currently configured
    var isAuthenticated: Bool { get }
    
    /// Configure authentication (API keys, username/password, etc.)
    func configureAuth(credentials: [String: String]) throws
    
    /// Fetch live aircraft within a bounding box
    func fetchAircraft(
        around center: CLLocationCoordinate2D,
        radiusDegrees: Double
    ) async throws -> [LiveAircraft]
    
    /// Minimum time interval between requests (rate limiting)
    var minRequestInterval: TimeInterval { get }
}

/// Supported aircraft data providers
enum AircraftProviderType: String, CaseIterable, Identifiable {
    case openSky = "opensky"
    case openSkyAuthenticated = "opensky_auth"
    case flightradar24 = "flightradar24"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .openSky:
            return "OpenSky Network (Anonymous)"
        case .openSkyAuthenticated:
            return "OpenSky Network (Authenticated)"
        case .flightradar24:
            return "Flightradar24"
        }
    }
    
    var description: String {
        switch self {
        case .openSky:
            return "Free, 1 request per 10 seconds"
        case .openSkyAuthenticated:
            return "Free with account, 1 request per second"
        case .flightradar24:
            return "Paid subscription, near real-time"
        }
    }
    
    var requiresAuth: Bool {
        switch self {
        case .openSky:
            return false
        case .openSkyAuthenticated:
            return true
        case .flightradar24:
            return true
        }
    }
    
    var authFields: [AuthField] {
        switch self {
        case .openSky:
            return []
        case .openSkyAuthenticated:
            return [
                AuthField(key: "username", label: "Username", isSecure: false),
                AuthField(key: "password", label: "Password", isSecure: true)
            ]
        case .flightradar24:
            return [
                AuthField(key: "api_key", label: "API Key", isSecure: true)
            ]
        }
    }
}

/// Authentication field definition
struct AuthField: Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let isSecure: Bool
}

