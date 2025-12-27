//
//  LiveAircraftService.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import CoreLocation

/// Service for fetching live aircraft positions
/// Uses the configured aircraft data provider
final class LiveAircraftService {
    static let shared = LiveAircraftService()
    
    private let providerManager = AircraftProviderManager.shared
    
    private init() {}
    
    /// Fetch live aircraft within a bounding box around coordinates
    /// - Parameters:
    ///   - center: Center coordinate (airport location)
    ///   - radiusDegrees: Radius in degrees (approximately 1 degree = 111km at equator)
    /// - Returns: Array of LiveAircraft objects
    func fetchAircraft(
        around center: CLLocationCoordinate2D,
        radiusDegrees: Double = 0.5 // ~55km radius
    ) async throws -> [LiveAircraft] {
        let provider = providerManager.provider
        return try await provider.fetchAircraft(around: center, radiusDegrees: radiusDegrees)
    }
}

// MARK: - Errors (for backward compatibility)
enum LiveAircraftError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case rateLimited
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL configuration"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimited:
            return "Rate limited. Please wait a moment."
        case .parseError:
            return "Failed to parse aircraft data"
        }
    }
}

