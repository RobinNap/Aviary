//
//  OpenSkyAircraftProvider.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import CoreLocation

/// OpenSky Network aircraft data provider
/// API Documentation: https://openskynetwork.github.io/opensky-api/rest.html
final class OpenSkyAircraftProvider: AircraftDataProvider {
    let name = "OpenSky Network"
    let requiresAuth: Bool
    let minRequestInterval: TimeInterval
    
    private let baseURL = "https://opensky-network.org/api"
    private let authURL = "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token"
    private let session: URLSession
    private var credentials: [String: String] = [:]
    private var accessToken: String?
    private var tokenExpiry: Date?
    private var lastRequestTime: Date?
    
    init(authenticated: Bool = false) {
        self.requiresAuth = authenticated
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        
        // Rate limiting based on OpenSky API docs:
        // Anonymous: 10 seconds between requests
        // Authenticated: 1 second between requests
        self.minRequestInterval = authenticated ? 1.0 : 10.0
    }
    
    var isAuthenticated: Bool {
        if !requiresAuth {
            return true // Anonymous doesn't need auth
        }
        // Check for OAuth2 credentials (clientId/clientSecret)
        let clientId = credentials["clientId"] ?? ""
        let clientSecret = credentials["clientSecret"] ?? ""
        // Also support legacy username/password for backward compatibility
        let username = credentials["username"] ?? ""
        let password = credentials["password"] ?? ""
        return (!clientId.isEmpty && !clientSecret.isEmpty) || (!username.isEmpty && !password.isEmpty)
    }
    
    func configureAuth(credentials: [String: String]) throws {
        if requiresAuth {
            // Support both OAuth2 (clientId/clientSecret) and legacy (username/password)
            let hasOAuth2 = !(credentials["clientId"]?.isEmpty ?? true) && !(credentials["clientSecret"]?.isEmpty ?? true)
            let hasLegacy = !(credentials["username"]?.isEmpty ?? true) && !(credentials["password"]?.isEmpty ?? true)
            
            guard hasOAuth2 || hasLegacy else {
                throw AircraftProviderError.missingCredentials
            }
        }
        self.credentials = credentials
        // Clear any existing token when credentials change
        self.accessToken = nil
        self.tokenExpiry = nil
    }
    
    /// Get OAuth2 access token using client credentials flow
    private func getAccessToken() async throws -> String {
        // Check if we have a valid cached token
        if let token = accessToken,
           let expiry = tokenExpiry,
           expiry > Date() {
            return token
        }
        
        guard let clientId = credentials["clientId"],
              let clientSecret = credentials["clientSecret"],
              !clientId.isEmpty && !clientSecret.isEmpty else {
            throw AircraftProviderError.missingCredentials
        }
        
        guard let url = URL(string: authURL) else {
            throw AircraftProviderError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // OAuth2 client credentials flow
        // URL encode the parameters properly
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret)
        ]
        // Remove the leading "?" from the query string
        let bodyString = components.url?.query ?? ""
        request.httpBody = bodyString.data(using: .utf8)
        
        print("OpenSkyAircraftProvider: Requesting OAuth2 access token")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AircraftProviderError.networkError(URLError(.badServerResponse))
            }
            
            if httpResponse.statusCode == 200 {
                // Parse token response
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let token = json["access_token"] as? String else {
                    throw AircraftProviderError.parseError
                }
                
                // Get token expiry (default to 1 hour if not provided)
                let expiresIn = json["expires_in"] as? Int ?? 3600
                self.accessToken = token
                self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn - 60)) // Refresh 1 minute before expiry
                
                print("OpenSkyAircraftProvider: Successfully obtained access token")
                return token
            } else {
                print("OpenSkyAircraftProvider: Failed to get access token, status: \(httpResponse.statusCode)")
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error_description"] as? String ?? errorJson["error"] as? String {
                    print("OpenSkyAircraftProvider: OAuth2 error: \(error)")
                }
                throw AircraftProviderError.authenticationFailed
            }
        } catch {
            throw AircraftProviderError.networkError(error)
        }
    }
    
    /// Test API credentials by making a simple request
    /// Returns true if credentials are valid, false otherwise
    func testCredentials(clientId: String, clientSecret: String) async throws -> Bool {
        guard requiresAuth else {
            // Anonymous mode doesn't need testing
            return true
        }
        
        // Test by getting an access token
        let testCredentials: [String: String] = ["clientId": clientId, "clientSecret": clientSecret]
        let originalCredentials = self.credentials
        self.credentials = testCredentials
        
        defer {
            self.credentials = originalCredentials
            self.accessToken = nil
            self.tokenExpiry = nil
        }
        
        do {
            _ = try await getAccessToken()
            return true
        } catch {
            return false
        }
    }
    
    /// Fetch aircraft within a bounding box
    /// Uses OpenSky API: GET /states/all with bounding box parameters
    func fetchAircraft(
        around center: CLLocationCoordinate2D,
        radiusDegrees: Double = 0.5
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
        // API parameters: lamin, lomin, lamax, lomax
        let lamin = center.latitude - radiusDegrees
        let lamax = center.latitude + radiusDegrees
        let lomin = center.longitude - radiusDegrees
        let lomax = center.longitude + radiusDegrees
        
        // Build URL: https://opensky-network.org/api/states/all?lamin=...&lomin=...&lamax=...&lomax=...
        guard var urlComponents = URLComponents(string: "\(baseURL)/states/all") else {
            throw AircraftProviderError.invalidURL
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "lamin", value: String(lamin)),
            URLQueryItem(name: "lamax", value: String(lamax)),
            URLQueryItem(name: "lomin", value: String(lomin)),
            URLQueryItem(name: "lomax", value: String(lomax))
        ]
        
        guard let url = urlComponents.url else {
            throw AircraftProviderError.invalidURL
        }
        
        // Make request
        var request = URLRequest(url: url)
        request.setValue("Aviary/1.0", forHTTPHeaderField: "User-Agent")
        
        // Add authentication ONLY if authenticated mode is enabled AND credentials are valid
        // For anonymous mode, do NOT send any Authorization header
        if requiresAuth && isAuthenticated {
            // Try OAuth2 first (clientId/clientSecret)
            if let clientId = credentials["clientId"],
               let clientSecret = credentials["clientSecret"],
               !clientId.isEmpty && !clientSecret.isEmpty {
                // Get OAuth2 access token
                do {
                    let token = try await getAccessToken()
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    print("OpenSkyAircraftProvider: Using OAuth2 authenticated mode")
                } catch {
                    print("OpenSkyAircraftProvider: Failed to get OAuth2 token: \(error)")
                    throw error
                }
            }
            // Fallback to legacy Basic Auth (username/password) for backward compatibility
            else if let username = credentials["username"],
                    let password = credentials["password"],
                    !username.isEmpty && !password.isEmpty {
                let authString = "\(username):\(password)"
                guard let authData = authString.data(using: .utf8) else {
                    throw AircraftProviderError.invalidCredentials
                }
                let base64Auth = authData.base64EncodedString()
                request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
                print("OpenSkyAircraftProvider: Using Basic Auth (legacy)")
            } else {
                print("OpenSkyAircraftProvider: Warning - authenticated mode selected but credentials missing/invalid")
                // Don't send auth header if credentials are invalid
            }
        } else {
            print("OpenSkyAircraftProvider: Using anonymous mode (no authentication)")
        }
        
        print("OpenSkyAircraftProvider: Fetching aircraft from \(url)")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AircraftProviderError.networkError(URLError(.badServerResponse))
            }
            
            print("OpenSkyAircraftProvider: Response status \(httpResponse.statusCode)")
            
            switch httpResponse.statusCode {
            case 200:
                return try parseStatesResponse(data: data)
            case 401:
                // 401 can mean:
                // 1. Authenticated mode but invalid credentials
                // 2. Anonymous mode but API is blocking (unlikely)
                if requiresAuth {
                    print("OpenSkyAircraftProvider: Authentication failed (401) - credentials are invalid")
                    // Try to parse error message if available
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let message = errorJson["message"] as? String {
                        print("OpenSkyAircraftProvider: API error: \(message)")
                    }
                    throw AircraftProviderError.authenticationFailed
                } else {
                    // For anonymous mode, 401 is unexpected - might be rate limiting or API issue
                    print("OpenSkyAircraftProvider: Unexpected 401 in anonymous mode - API may be blocking requests")
                    // Try to parse error message if available
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let message = errorJson["message"] as? String {
                        print("OpenSkyAircraftProvider: API error: \(message)")
                    }
                    throw AircraftProviderError.networkError(URLError(.userAuthenticationRequired))
                }
            case 429:
                print("OpenSkyAircraftProvider: Rate limited (429)")
                throw AircraftProviderError.rateLimited
            default:
                print("OpenSkyAircraftProvider: Unexpected status code \(httpResponse.statusCode)")
                throw AircraftProviderError.networkError(URLError(.badServerResponse))
            }
        } catch let error as AircraftProviderError {
            throw error
        } catch {
            throw AircraftProviderError.networkError(error)
        }
    }
    
    /// Parse OpenSky states response
    /// Response format per API docs:
    /// - time: integer - timestamp
    /// - states: array of state vectors
    /// Each state vector is an array with indices 0-17 containing flight data
    private func parseStatesResponse(data: Data) throws -> [LiveAircraft] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let states = json["states"] as? [[Any]] else {
            print("OpenSkyAircraftProvider: No states in response or invalid JSON")
            return []
        }
        
        let timestamp = (json["time"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        
        print("OpenSkyAircraftProvider: Parsing \(states.count) aircraft")
        
        return states.compactMap { state -> LiveAircraft? in
            // State vector indices per API documentation:
            // 0: icao24 (string)
            // 1: callsign (string, nullable)
            // 2: origin_country (string)
            // 3: time_position (int, nullable)
            // 4: last_contact (int)
            // 5: longitude (float, nullable)
            // 6: latitude (float, nullable)
            // 7: baro_altitude (float, nullable)
            // 8: on_ground (boolean)
            // 9: velocity (float, nullable) - m/s
            // 10: true_track (float, nullable) - degrees
            // 11: vertical_rate (float, nullable) - m/s
            // 12-17: additional fields
            
            guard state.count >= 12,
                  let icao24 = state[0] as? String,
                  let longitude = state[5] as? Double,
                  let latitude = state[6] as? Double else {
                return nil
            }
            
            // Validate coordinates
            guard longitude >= -180 && longitude <= 180,
                  latitude >= -90 && latitude <= 90 else {
                return nil
            }
            
            let callsign = (state[1] as? String)?.trimmingCharacters(in: .whitespaces)
            let originCountry = (state[2] as? String) ?? "Unknown"
            let altitude = state[7] as? Double  // baro_altitude in meters
            let onGround = (state[8] as? Bool) ?? false
            let velocity = state[9] as? Double  // m/s
            let heading = state[10] as? Double  // true_track in degrees
            let verticalRate = state[11] as? Double  // m/s
            
            return LiveAircraft(
                id: icao24,
                callsign: callsign?.isEmpty == true ? nil : callsign,
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

// MARK: - Provider Errors
enum AircraftProviderError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case rateLimited
    case missingCredentials
    case invalidCredentials
    case authenticationFailed
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL configuration"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimited:
            return "Rate limited. Please wait a moment."
        case .missingCredentials:
            return "Missing required credentials"
        case .invalidCredentials:
            return "Invalid credentials format"
        case .authenticationFailed:
            return "Authentication failed. Please check your username and password in Settings. Make sure you have a valid account at opensky-network.org."
        case .parseError:
            return "Failed to parse aircraft data"
        }
    }
}
