//
//  LiveAircraftService.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import CoreLocation

/// Service for fetching live aircraft positions from OpenSky Network
/// Uses the /states/all endpoint for real-time aircraft tracking
/// API Documentation: https://openskynetwork.github.io/opensky-api/rest.html
final class LiveAircraftService {
    static let shared = LiveAircraftService()
    
    private let baseURL = "https://opensky-network.org/api/states/all"
    private let session: URLSession
    
    // Rate limiting - OpenSky allows anonymous requests every 10 seconds
    // Using 2 seconds for near real-time updates while staying within reasonable limits
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 2
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }
    
    /// Fetch live aircraft within a bounding box around coordinates
    /// - Parameters:
    ///   - center: Center coordinate (airport location)
    ///   - radiusDegrees: Radius in degrees (approximately 1 degree = 111km at equator)
    /// - Returns: Array of LiveAircraft objects
    func fetchAircraft(
        around center: CLLocationCoordinate2D,
        radiusDegrees: Double = 0.5 // ~55km radius
    ) async throws -> [LiveAircraft] {
        // Rate limiting check
        if let lastRequest = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastRequest)
            if elapsed < minRequestInterval {
                let waitTime = minRequestInterval - elapsed
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
        
        lastRequestTime = Date()
        
        // Calculate bounding box
        let lamin = center.latitude - radiusDegrees
        let lamax = center.latitude + radiusDegrees
        let lomin = center.longitude - radiusDegrees
        let lomax = center.longitude + radiusDegrees
        
        // Build URL with bounding box
        guard var urlComponents = URLComponents(string: baseURL) else {
            throw LiveAircraftError.invalidURL
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "lamin", value: String(lamin)),
            URLQueryItem(name: "lamax", value: String(lamax)),
            URLQueryItem(name: "lomin", value: String(lomin)),
            URLQueryItem(name: "lomax", value: String(lomax))
        ]
        
        guard let url = urlComponents.url else {
            throw LiveAircraftError.invalidURL
        }
        
        // Make request
        var request = URLRequest(url: url)
        request.setValue("Aviary/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LiveAircraftError.networkError(URLError(.badServerResponse))
            }
            
            switch httpResponse.statusCode {
            case 200:
                return try parseStatesResponse(data: data)
            case 429:
                throw LiveAircraftError.rateLimited
            default:
                throw LiveAircraftError.networkError(URLError(.badServerResponse))
            }
        } catch let error as LiveAircraftError {
            throw error
        } catch {
            throw LiveAircraftError.networkError(error)
        }
    }
    
    /// Parse OpenSky states response
    /// Response format: { "time": int, "states": [[...], [...], ...] }
    /// State vector indices:
    /// 0: icao24, 1: callsign, 2: origin_country, 3: time_position, 4: last_contact,
    /// 5: longitude, 6: latitude, 7: baro_altitude, 8: on_ground, 9: velocity,
    /// 10: true_track, 11: vertical_rate, 12-16: other fields
    private func parseStatesResponse(data: Data) throws -> [LiveAircraft] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let states = json["states"] as? [[Any]] else {
            // No aircraft in area or invalid response
            return []
        }
        
        let timestamp = (json["time"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        
        return states.compactMap { state -> LiveAircraft? in
            // Validate required fields
            guard state.count >= 12,
                  let icao24 = state[0] as? String,
                  let longitude = state[5] as? Double,
                  let latitude = state[6] as? Double else {
                return nil
            }
            
            // Skip invalid coordinates
            guard longitude >= -180 && longitude <= 180,
                  latitude >= -90 && latitude <= 90 else {
                return nil
            }
            
            let callsign = state[1] as? String
            let originCountry = (state[2] as? String) ?? "Unknown"
            let altitude = state[7] as? Double
            let onGround = (state[8] as? Bool) ?? false
            let velocity = state[9] as? Double
            let heading = state[10] as? Double
            let verticalRate = state[11] as? Double
            
            return LiveAircraft(
                id: icao24,
                callsign: callsign,
                originCountry: originCountry,
                longitude: longitude,
                latitude: latitude,
                altitude: altitude,
                onGround: onGround,
                velocity: velocity,
                heading: heading,
                verticalRate: verticalRate,
                lastUpdate: timestamp
            )
        }
    }
}

// MARK: - Errors
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

