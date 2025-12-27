//
//  AviationstackAircraftProvider.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import CoreLocation

/// Aviationstack aircraft data provider
/// API Documentation: https://aviationstack.com/documentation
/// Free plan: 100 requests/month, Paid plans starting at $49.99/month
final class AviationstackAircraftProvider: AircraftDataProvider {
    let name = "Aviationstack"
    let requiresAuth = true
    let minRequestInterval: TimeInterval = 1.0 // 1 second between requests (rate limit depends on plan)
    
    private let baseURL = "https://api.aviationstack.com/v1"
    private let session: URLSession
    private var apiKey: String?
    private var lastRequestTime: Date?
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        
        // Load API key from settings if available
        updateCredentials()
        
        // Listen for credential changes
        NotificationCenter.default.addObserver(
            forName: .aircraftProviderChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateCredentials()
        }
    }
    
    /// Update credentials from settings
    private func updateCredentials() {
        let settings = AircraftSettings.shared
        if let credentials = settings.getCredentials(for: .aviationstack) {
            self.apiKey = credentials["api_key"]
        } else {
            self.apiKey = nil
        }
    }
    
    var isAuthenticated: Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }
    
    func configureAuth(credentials: [String: String]) throws {
        guard let key = credentials["api_key"], !key.isEmpty else {
            throw AircraftProviderError.missingCredentials
        }
        self.apiKey = key
    }
    
    func fetchAircraft(
        around center: CLLocationCoordinate2D,
        radiusDegrees: Double = 0.5
    ) async throws -> [LiveAircraft] {
        guard isAuthenticated else {
            throw AircraftProviderError.missingCredentials
        }
        
        // Rate limiting check
        if let lastRequest = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastRequest)
            if elapsed < minRequestInterval {
                let waitTime = minRequestInterval - elapsed
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
        
        lastRequestTime = Date()
        
        // Aviationstack doesn't have a direct "states/all" endpoint like OpenSky
        // Instead, we need to use the flights endpoint with location parameters
        // For aircraft tracking, we'll use the flights endpoint with lat/lon bounds
        
        // Calculate bounding box
        let lamin = center.latitude - radiusDegrees
        let lamax = center.latitude + radiusDegrees
        let lomin = center.longitude - radiusDegrees
        let lomax = center.longitude + radiusDegrees
        
        // Build URL - Aviationstack flights endpoint
        guard var urlComponents = URLComponents(string: "\(baseURL)/flights") else {
            throw AircraftProviderError.invalidURL
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "access_key", value: apiKey),
            URLQueryItem(name: "limit", value: "100"), // Max results per request
            // Note: Aviationstack may not support direct lat/lon bounds in flights endpoint
            // This is a placeholder - actual implementation depends on API documentation
        ]
        
        guard let url = urlComponents.url else {
            throw AircraftProviderError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Aviary/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AircraftProviderError.networkError(URLError(.badServerResponse))
            }
            
            switch httpResponse.statusCode {
            case 200:
                return try parseAviationstackResponse(data: data, center: center, radiusDegrees: radiusDegrees)
            case 401:
                throw AircraftProviderError.authenticationFailed
            case 429:
                throw AircraftProviderError.rateLimited
            default:
                // Check for error in response body
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorData["error"] as? [String: Any],
                   let info = error["info"] as? String {
                    throw AircraftProviderError.networkError(NSError(
                        domain: "AviationstackError",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: info]
                    ))
                }
                throw AircraftProviderError.networkError(URLError(.badServerResponse))
            }
        } catch let error as AircraftProviderError {
            throw error
        } catch {
            throw AircraftProviderError.networkError(error)
        }
    }
    
    /// Parse Aviationstack API response into LiveAircraft objects
    /// Note: This implementation is based on typical Aviationstack response structure
    /// Actual structure may vary - consult API documentation for exact format
    private func parseAviationstackResponse(
        data: Data,
        center: CLLocationCoordinate2D,
        radiusDegrees: Double
    ) throws -> [LiveAircraft] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            // If no "data" array, might be pagination or different structure
            return []
        }
        
        let timestamp = Date()
        
        return dataArray.compactMap { flightData -> LiveAircraft? in
            // Aviationstack flight data structure
            // We need to extract aircraft position from flight data
            guard let flight = flightData["flight"] as? [String: Any],
                  let aircraft = flight["aircraft"] as? [String: Any] else {
                return nil
            }
            
            // Get aircraft registration/ICAO
            let icao24 = aircraft["icao24"] as? String ?? aircraft["registration"] as? String
            guard let aircraftId = icao24, !aircraftId.isEmpty else {
                return nil
            }
            
            // Get flight details
            let callsign = flight["iata"] as? String ?? flight["icao"] as? String
            let airline = flight["airline"] as? [String: Any]
            let airlineName = airline?["name"] as? String
            
            // Get live position if available
            let live = flight["live"] as? [String: Any]
            let latitude = live?["latitude"] as? Double
            let longitude = live?["longitude"] as? Double
            let altitude = live?["altitude"] as? Double
            let speed = live?["speed_horizontal"] as? Double
            let heading = live?["direction"] as? Double
            let verticalRate = live?["speed_vertical"] as? Double
            let onGround = (live?["is_ground"] as? Bool) ?? false
            
            // Filter by location if we have coordinates
            if let lat = latitude, let lon = longitude {
                let distance = sqrt(
                    pow(lat - center.latitude, 2) + pow(lon - center.longitude, 2)
                )
                if distance > radiusDegrees {
                    return nil // Outside bounding box
                }
                
                return LiveAircraft(
                    id: aircraftId,
                    callsign: callsign,
                    originCountry: airlineName ?? "Unknown",
                    longitude: lon,
                    latitude: lat,
                    altitude: altitude,
                    onGround: onGround,
                    velocity: speed,
                    heading: heading,
                    verticalRate: verticalRate,
                    lastUpdate: timestamp
                )
            }
            
            // If no live position, we can't create a LiveAircraft
            return nil
        }
    }
}

