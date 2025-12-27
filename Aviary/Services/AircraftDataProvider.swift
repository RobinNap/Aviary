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
/// Using OpenSky Network API: https://openskynetwork.github.io/opensky-api/rest.html
enum AircraftProviderType: String, CaseIterable, Identifiable {
    case openSky = "opensky"
    case openSkyAuthenticated = "opensky_auth"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .openSky:
            return "OpenSky Network (Free)"
        case .openSkyAuthenticated:
            return "OpenSky Network (Authenticated)"
        }
    }
    
    var description: String {
        switch self {
        case .openSky:
            return "Free, anonymous access - 1 request per 10 seconds"
        case .openSkyAuthenticated:
            return "Free account with OAuth2 credentials - 1 request per second, more data"
        }
    }
    
    var requiresAuth: Bool {
        switch self {
        case .openSky:
            return false
        case .openSkyAuthenticated:
            return true
        }
    }
    
    var authFields: [AuthField] {
        switch self {
        case .openSky:
            return []
        case .openSkyAuthenticated:
            return [
                AuthField(key: "clientId", label: "Client ID", isSecure: false),
                AuthField(key: "clientSecret", label: "Client Secret", isSecure: true)
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
