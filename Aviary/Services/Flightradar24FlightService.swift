//
//  Flightradar24FlightService.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation

/// Flight service implementation using Flightradar24 API
/// API Documentation: https://www.flightradar24.com/blog/b2b/flightradar24-api/
/// Note: Requires API subscription and token
final class Flightradar24FlightService: FlightService {
    static let shared = Flightradar24FlightService()
    
    private let baseURL = "https://api.flightradar24.com/common/v1"
    private let session: URLSession
    private let decoder: JSONDecoder
    
    // Rate limiting
    private var lastRequestTime: Date?
    private var consecutiveFailures: Int = 0
    private let minRequestInterval: TimeInterval = 0.5 // Faster with paid API
    private let maxBackoffInterval: TimeInterval = 60 // Max 1 minute backoff
    
    private var apiKey: String?
    private let settings = AircraftSettings.shared
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        
        self.decoder = JSONDecoder()
        
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
    
    var isAuthenticated: Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }
    
    func fetchFlights(
        airportIcao: String,
        direction: FlightDirection,
        from: Date,
        to: Date
    ) async throws -> [Flight] {
        guard isAuthenticated else {
            throw FlightServiceError.networkError(URLError(.userAuthenticationRequired))
        }
        
        // Validate ICAO code
        guard airportIcao.count >= 3 && airportIcao.count <= 4 else {
            throw FlightServiceError.invalidAirportCode
        }
        
        // Rate limiting check with exponential backoff
        if let lastRequest = lastRequestTime {
            let baseInterval = minRequestInterval
            let backoffMultiplier = pow(2.0, Double(min(consecutiveFailures, 4))) // Cap at 2^4 = 16x
            let requiredInterval = baseInterval * backoffMultiplier
            let maxInterval = min(requiredInterval, maxBackoffInterval)
            
            let elapsed = Date().timeIntervalSince(lastRequest)
            if elapsed < maxInterval {
                let waitTime = maxInterval - elapsed
                print("Flightradar24FlightService: Rate limiting - waiting \(waitTime) seconds (failures: \(consecutiveFailures))")
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
        
        lastRequestTime = Date()
        
        // Build URL - Flightradar24 API endpoint structure
        // Note: Actual endpoint may vary based on API version and documentation
        let endpoint = direction == .arrival ? "airport/arrivals" : "airport/departures"
        
        guard var urlComponents = URLComponents(string: "\(baseURL)/\(endpoint)") else {
            throw FlightServiceError.networkError(URLError(.badURL))
        }
        
        let beginTimestamp = Int(from.timeIntervalSince1970)
        let endTimestamp = Int(to.timeIntervalSince1970)
        
        urlComponents.queryItems = [
            URLQueryItem(name: "airport", value: airportIcao.uppercased()),
            URLQueryItem(name: "from", value: String(beginTimestamp)),
            URLQueryItem(name: "to", value: String(endTimestamp)),
            URLQueryItem(name: "token", value: apiKey)
        ]
        
        guard let url = urlComponents.url else {
            throw FlightServiceError.networkError(URLError(.badURL))
        }
        
        // Make request
        do {
            var request = URLRequest(url: url)
            request.setValue("Aviary/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FlightServiceError.networkError(URLError(.badServerResponse))
            }
            
            switch httpResponse.statusCode {
            case 200:
                consecutiveFailures = 0 // Reset on success
                return try parseFlightradar24Response(data: data, direction: direction, airportIcao: airportIcao)
            case 401:
                consecutiveFailures += 1
                throw FlightServiceError.networkError(URLError(.userAuthenticationRequired))
            case 429:
                consecutiveFailures += 1
                print("Flightradar24FlightService: Rate limited (429) - consecutive failures: \(consecutiveFailures)")
                throw FlightServiceError.rateLimited
            case 404:
                consecutiveFailures = 0 // Not a failure, just no data
                return [] // No data for this airport
            default:
                consecutiveFailures += 1
                throw FlightServiceError.networkError(URLError(.badServerResponse))
            }
        } catch let error as FlightServiceError {
            throw error
        } catch {
            throw FlightServiceError.networkError(error)
        }
    }
    
    /// Parse Flightradar24 API response into Flight objects
    /// Note: This is a placeholder implementation - actual structure depends on Flightradar24 API documentation
    private func parseFlightradar24Response(data: Data, direction: FlightDirection, airportIcao: String) throws -> [Flight] {
        do {
            // Flightradar24 API response structure would need to be determined from actual API documentation
            // This is a placeholder that shows the expected structure
            
            // Try to decode as JSON first to see the structure
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Common Flightradar24 response structure might be:
                // { "result": { "response": { "airport": { "pluginData": { "schedule": { "arrivals": [...] or "departures": [...] } } } } } }
                
                // For now, return empty array with a note that this needs actual API documentation
                // In production, this would parse the actual Flightradar24 response format
                print("Flightradar24FlightService: API response received but parsing not yet implemented - needs API documentation")
                return []
            }
            
            // If we can't parse, return empty
            return []
        } catch {
            throw FlightServiceError.parseError(error)
        }
    }
    
    /// Update API key (called when credentials change)
    func updateCredentials() {
        if let credentials = settings.getCredentials(for: .flightradar24) {
            self.apiKey = credentials["api_key"]
        } else {
            self.apiKey = nil
        }
    }
}

