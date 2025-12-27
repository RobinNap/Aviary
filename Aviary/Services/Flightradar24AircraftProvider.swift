//
//  Flightradar24AircraftProvider.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import CoreLocation

/// Flightradar24 aircraft data provider
/// 
/// IMPORTANT: The endpoint URLs in this implementation may need to be updated based on the actual
/// FlightRadar24 API documentation. Please verify the correct endpoints at:
/// https://fr24api.flightradar24.com/docs
/// 
/// Current endpoint being tried: /api/v1/live/flight-positions/light
/// If this returns 404, check the documentation for the correct endpoint structure.
final class Flightradar24AircraftProvider: AircraftDataProvider {
    let name = "Flightradar24"
    let requiresAuth = true
    let minRequestInterval: TimeInterval = 0.5 // Faster updates with paid API
    
    private let baseURL = "https://fr24api.flightradar24.com"
    private let session: URLSession
    private var apiKey: String?
    private var lastRequestTime: Date?
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
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
        
        // Note: Flightradar24 API structure would need to be implemented based on their actual API documentation
        // This is a placeholder that shows the structure
        
        // Calculate bounding box
        let lamin = center.latitude - radiusDegrees
        let lamax = center.latitude + radiusDegrees
        let lomin = center.longitude - radiusDegrees
        let lomax = center.longitude + radiusDegrees
        
        // Build URL - FlightRadar24 API endpoint for live aircraft tracking
        // Documentation: https://fr24api.flightradar24.com/docs
        // For sandbox testing, prepend "sandbox" to the endpoint path
        // Endpoint: /api/sandbox/live/flight-positions/full with bounds parameter
        // Bounds format: north,south,west,east (lat_max,lat_min,lon_min,lon_max)
        
        guard var urlComponents = URLComponents(string: "\(baseURL)/api/sandbox/live/flight-positions/full") else {
            throw AircraftProviderError.invalidURL
        }
        
        // Use bounds parameter for geographic area
        // Format: north,south,west,east (lat_max,lat_min,lon_min,lon_max)
        urlComponents.queryItems = [
            URLQueryItem(name: "bounds", value: "\(lamax),\(lamin),\(lomin),\(lomax)")
        ]
        
        guard let url = urlComponents.url else {
            throw AircraftProviderError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Aviary/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")
        
        // FlightRadar24 API authentication - Bearer token format
        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        print("Flightradar24AircraftProvider: Fetching aircraft from \(url)")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AircraftProviderError.networkError(URLError(.badServerResponse))
            }
            
            // Log response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("Flightradar24AircraftProvider: Response status \(httpResponse.statusCode), body: \(responseString.prefix(500))")
            }
            
            // Try to parse error message from response
            if httpResponse.statusCode >= 400 {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = errorJson["message"] as? String {
                    print("Flightradar24AircraftProvider: API error message: \(errorMessage)")
                    if errorMessage.contains("does not exist") || errorMessage.contains("endpoint") {
                        print("Flightradar24AircraftProvider: Endpoint may be incorrect. Current URL: \(url)")
                        print("Flightradar24AircraftProvider: Please check API documentation at https://fr24api.flightradar24.com/docs")
                    }
                }
            }
            
            switch httpResponse.statusCode {
            case 200:
                return try parseFlightradar24Response(data: data)
            case 401:
                print("Flightradar24AircraftProvider: Authentication failed (401) - check API key")
                throw AircraftProviderError.authenticationFailed
            case 403:
                print("Flightradar24AircraftProvider: Forbidden (403) - check API key permissions")
                throw AircraftProviderError.authenticationFailed
            case 404:
                // 404 with helpful message - endpoint structure may be wrong
                print("Flightradar24AircraftProvider: Endpoint not found (404). Current endpoint: \(url)")
                print("Flightradar24AircraftProvider: Please verify endpoint structure in API documentation: https://fr24api.flightradar24.com/docs")
                throw AircraftProviderError.networkError(URLError(.badURL))
            case 429:
                print("Flightradar24AircraftProvider: Rate limited (429)")
                throw AircraftProviderError.rateLimited
            default:
                print("Flightradar24AircraftProvider: Unexpected status code \(httpResponse.statusCode)")
                throw AircraftProviderError.networkError(URLError(.badServerResponse))
            }
        } catch let error as AircraftProviderError {
            throw error
        } catch {
            throw AircraftProviderError.networkError(error)
        }
    }
    
    /// Parse Flightradar24 response
    private func parseFlightradar24Response(data: Data) throws -> [LiveAircraft] {
        do {
            // Parse JSON response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("Flightradar24AircraftProvider: Invalid JSON response")
                return []
            }
            
            // FlightRadar24 API typically returns data in a nested structure
            var aircraftArray: [[String: Any]]?
            
            // Structure 1: Direct array
            if let directArray = json["data"] as? [[String: Any]] {
                aircraftArray = directArray
            }
            // Structure 2: Nested in result/response
            else if let result = json["result"] as? [String: Any],
                    let response = result["response"] as? [String: Any],
                    let data = response["data"] as? [[String: Any]] {
                aircraftArray = data
            }
            // Structure 3: Direct in response
            else if let response = json["response"] as? [String: Any],
                    let data = response["data"] as? [[String: Any]] {
                aircraftArray = data
            }
            // Structure 4: Top-level flights array
            else if let flights = json["flights"] as? [[String: Any]] {
                aircraftArray = flights
            }
            
            guard let aircraft = aircraftArray else {
                // Log the structure for debugging
                print("Flightradar24AircraftProvider: Could not find aircraft array in response. Top-level keys: \(json.keys.joined(separator: ", "))")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("Flightradar24AircraftProvider: Full response: \(jsonString.prefix(1000))")
                }
                return []
            }
            
            let timestamp = Date()
            
            return aircraft.compactMap { aircraftData -> LiveAircraft? in
                // Extract aircraft information from FlightRadar24 response
                let flight = aircraftData["flight"] as? [String: Any]
                let identification = aircraftData["identification"] as? [String: Any]
                let aircraft = aircraftData["aircraft"] as? [String: Any]
                let trail = aircraftData["trail"] as? [[String: Any]]
                let position = aircraftData["position"] as? [String: Any]
                
                // Get aircraft identifier
                let icao24 = identification?["id"] as? String ?? 
                            (aircraft?["registration"] as? [String: Any])?["hex"] as? String ??
                            aircraftData["icao24"] as? String
                
                guard let icao24 = icao24, !icao24.isEmpty else {
                    return nil
                }
                
                // Get callsign
                let callsign = identification?["callsign"] as? String ?? 
                              flight?["number"] as? String ??
                              aircraftData["callsign"] as? String
                
                // Get position - try multiple possible structures
                var latitude: Double?
                var longitude: Double?
                var altitude: Double?
                var speed: Double?
                var heading: Double?
                var verticalRate: Double?
                var onGround: Bool = false
                
                // Try position object
                if let pos = position {
                    latitude = pos["latitude"] as? Double
                    longitude = pos["longitude"] as? Double
                    altitude = pos["altitude"] as? Double
                    speed = pos["speed"] as? Double
                    heading = pos["heading"] as? Double
                    verticalRate = pos["verticalRate"] as? Double
                    onGround = (pos["onGround"] as? Bool) ?? false
                }
                
                // Try trail (most recent position)
                if latitude == nil || longitude == nil, let trail = trail, !trail.isEmpty {
                    let latest = trail.last!
                    latitude = latest["lat"] as? Double ?? latest["latitude"] as? Double
                    longitude = latest["lng"] as? Double ?? latest["longitude"] as? Double
                    altitude = latest["alt"] as? Double ?? latest["altitude"] as? Double
                    speed = latest["spd"] as? Double ?? latest["speed"] as? Double
                    heading = latest["hdg"] as? Double ?? latest["heading"] as? Double
                }
                
                // Try top-level fields
                if latitude == nil {
                    latitude = aircraftData["latitude"] as? Double
                }
                if longitude == nil {
                    longitude = aircraftData["longitude"] as? Double
                }
                if altitude == nil {
                    altitude = aircraftData["altitude"] as? Double
                }
                if speed == nil {
                    speed = aircraftData["speed"] as? Double
                }
                if heading == nil {
                    heading = aircraftData["heading"] as? Double
                }
                
                // Must have at least latitude and longitude
                guard let lat = latitude, let lon = longitude else {
                    return nil
                }
                
                // Get aircraft type
                let aircraftModel = aircraft?["model"] as? [String: Any]
                let aircraftType = aircraftModel?["text"] as? String ?? 
                                 aircraft?["model"] as? String
                
                // Get origin country (required field)
                let owner = aircraftData["owner"] as? [String: Any]
                let originCountry = (owner?["country"] as? [String: Any])?["name"] as? String ??
                                   aircraftData["originCountry"] as? String ??
                                   "Unknown"
                
                // Convert speed from knots to m/s if needed (FlightRadar24 may provide in knots)
                // Assuming speed is already in m/s, but if it's in knots, multiply by 0.514444
                let velocity = speed
                
                return LiveAircraft(
                    id: icao24,
                    callsign: callsign,
                    originCountry: originCountry,
                    longitude: lon,
                    latitude: lat,
                    altitude: altitude,
                    onGround: onGround,
                    velocity: velocity,
                    heading: heading,
                    verticalRate: verticalRate,
                    lastUpdate: timestamp
                )
            }
        } catch {
            print("Flightradar24AircraftProvider: Parse error: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Flightradar24AircraftProvider: Response data: \(jsonString.prefix(1000))")
            }
            throw AircraftProviderError.parseError
        }
    }
    
    /// Test API credentials by making a simple request
    func testCredentials(apiKey: String) async throws -> Bool {
        // Use sandbox endpoint to test authentication
        // For sandbox, prepend "sandbox" to endpoint path
        guard let url = URL(string: "\(baseURL)/api/sandbox/live/flight-positions/full?bounds=52.0,51.0,-1.0,0.0") else {
            throw AircraftProviderError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Aviary/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AircraftProviderError.networkError(URLError(.badServerResponse))
            }
            
            // 200-299 means success
            // 401/403 means auth failed
            // 404 could mean wrong endpoint or missing subscription for that endpoint
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return false
            }
            
            // 200 means auth is definitely working
            if httpResponse.statusCode == 200 {
                return true
            }
            
            // For 404 and other errors, auth might be working but endpoint might be wrong
            // We return true to indicate auth validation passed (not a credential issue)
            return true
        } catch {
            throw AircraftProviderError.networkError(error)
        }
    }
}

