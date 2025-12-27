//
//  OpenSkyAircraftProvider.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import CoreLocation

/// OpenSky Network aircraft data provider
final class OpenSkyAircraftProvider: AircraftDataProvider {
    let name = "OpenSky Network"
    let requiresAuth: Bool
    let minRequestInterval: TimeInterval
    
    private let baseURL: String
    private let session: URLSession
    private var credentials: [String: String] = [:]
    private var lastRequestTime: Date?
    
    init(authenticated: Bool = false) {
        self.requiresAuth = authenticated
        self.baseURL = "https://opensky-network.org/api/states/all"
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        
        // Rate limiting: 10 seconds for anonymous, 1 second for authenticated
        self.minRequestInterval = authenticated ? 1.0 : 10.0
    }
    
    var isAuthenticated: Bool {
        if !requiresAuth {
            return true // Anonymous doesn't need auth
        }
        let username = credentials["username"] ?? ""
        let password = credentials["password"] ?? ""
        return !username.isEmpty && !password.isEmpty
    }
    
    func configureAuth(credentials: [String: String]) throws {
        if requiresAuth {
            guard let username = credentials["username"], !username.isEmpty,
                  let password = credentials["password"], !password.isEmpty else {
                throw AircraftProviderError.missingCredentials
            }
        }
        self.credentials = credentials
    }
    
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
        let lamin = center.latitude - radiusDegrees
        let lamax = center.latitude + radiusDegrees
        let lomin = center.longitude - radiusDegrees
        let lomax = center.longitude + radiusDegrees
        
        // Build URL
        guard var urlComponents = URLComponents(string: baseURL) else {
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
        
        // Add authentication if configured
        if requiresAuth, isAuthenticated,
           let username = credentials["username"],
           let password = credentials["password"] {
            let authString = "\(username):\(password)"
            guard let authData = authString.data(using: .utf8) else {
                throw AircraftProviderError.invalidCredentials
            }
            let base64Auth = authData.base64EncodedString()
            request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AircraftProviderError.networkError(URLError(.badServerResponse))
            }
            
            switch httpResponse.statusCode {
            case 200:
                return try parseStatesResponse(data: data)
            case 401:
                throw AircraftProviderError.authenticationFailed
            case 429:
                throw AircraftProviderError.rateLimited
            default:
                throw AircraftProviderError.networkError(URLError(.badServerResponse))
            }
        } catch let error as AircraftProviderError {
            throw error
        } catch {
            throw AircraftProviderError.networkError(error)
        }
    }
    
    /// Parse OpenSky states response
    private func parseStatesResponse(data: Data) throws -> [LiveAircraft] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let states = json["states"] as? [[Any]] else {
            return []
        }
        
        let timestamp = (json["time"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        
        return states.compactMap { state -> LiveAircraft? in
            guard state.count >= 12,
                  let icao24 = state[0] as? String,
                  let longitude = state[5] as? Double,
                  let latitude = state[6] as? Double else {
                return nil
            }
            
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
            return "Authentication failed. Please check your credentials."
        case .parseError:
            return "Failed to parse aircraft data"
        }
    }
}

