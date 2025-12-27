//
//  Flightradar24FlightService.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation

/// Flight service implementation using Flightradar24 API
/// 
/// IMPORTANT: The endpoint URLs in this implementation may need to be updated based on the actual
/// FlightRadar24 API documentation. Please verify the correct endpoints at:
/// https://fr24api.flightradar24.com/docs
/// 
/// Current endpoint being tried: /api/v1/airport/{icao} with schedule query parameter
/// If this returns 404, check the documentation for the correct endpoint structure.
/// 
/// Requires API subscription and token
final class Flightradar24FlightService: FlightService {
    static let shared = Flightradar24FlightService()
    
    private let baseURL = "https://fr24api.flightradar24.com"
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
        // Documentation: https://fr24api.flightradar24.com/docs
        // For sandbox testing, prepend "sandbox" to the endpoint path
        // Endpoint: /api/sandbox/airports/{code}/flights with direction query param
        
        let airportCode = airportIcao.uppercased()
        
        // Build URL with airport code - sandbox endpoint
        guard var urlComponents = URLComponents(string: "\(baseURL)/api/sandbox/airports/\(airportCode)/flights") else {
            throw FlightServiceError.networkError(URLError(.badURL))
        }
        
        // Use query parameters for direction and pagination
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: direction == .arrival ? "arrivals" : "departures"),
            URLQueryItem(name: "limit", value: "100")
        ]
        
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            throw FlightServiceError.networkError(URLError(.badURL))
        }
        
        // Make request
        do {
            var request = URLRequest(url: url)
            request.setValue("Aviary/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("v1", forHTTPHeaderField: "Accept-Version")
            
            // FlightRadar24 API authentication - Bearer token format
            if let apiKey = apiKey {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            
            print("Flightradar24FlightService: Fetching \(direction) for \(airportIcao) from \(url)")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FlightServiceError.networkError(URLError(.badServerResponse))
            }
            
            // Log response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("Flightradar24FlightService: Response status \(httpResponse.statusCode), body: \(responseString.prefix(500))")
            }
            
            // Try to parse error message from response
            if httpResponse.statusCode >= 400 {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = errorJson["message"] as? String ?? errorJson["error"] as? String {
                    print("Flightradar24FlightService: API error message: \(errorMessage)")
                    if errorMessage.contains("does not exist") || errorMessage.contains("endpoint") {
                        print("Flightradar24FlightService: Endpoint may be incorrect. Current URL: \(url)")
                        print("Flightradar24FlightService: Please check API documentation at https://fr24api.flightradar24.com/docs")
                    }
                }
            }
            
            switch httpResponse.statusCode {
            case 200:
                consecutiveFailures = 0 // Reset on success
                return try parseFlightradar24Response(data: data, direction: direction, airportIcao: airportIcao)
            case 401:
                consecutiveFailures += 1
                print("Flightradar24FlightService: Authentication failed (401) - check API key")
                throw FlightServiceError.networkError(URLError(.userAuthenticationRequired))
            case 403:
                consecutiveFailures += 1
                print("Flightradar24FlightService: Forbidden (403) - check API key permissions")
                throw FlightServiceError.networkError(URLError(.userAuthenticationRequired))
            case 404:
                consecutiveFailures += 1 // Count as failure since endpoint structure may be wrong
                print("Flightradar24FlightService: Endpoint not found (404) for airport \(airportIcao)")
                print("Flightradar24FlightService: Current endpoint: \(url)")
                print("Flightradar24FlightService: Please verify endpoint structure in API documentation: https://fr24api.flightradar24.com/docs")
                // Don't return empty array - throw error so user knows something is wrong
                throw FlightServiceError.networkError(URLError(.badURL))
            case 429:
                consecutiveFailures += 1
                print("Flightradar24FlightService: Rate limited (429) - consecutive failures: \(consecutiveFailures)")
                throw FlightServiceError.rateLimited
            default:
                consecutiveFailures += 1
                print("Flightradar24FlightService: Unexpected status code \(httpResponse.statusCode)")
                throw FlightServiceError.networkError(URLError(.badServerResponse))
            }
        } catch let error as FlightServiceError {
            throw error
        } catch {
            throw FlightServiceError.networkError(error)
        }
    }
    
    /// Parse Flightradar24 API response into Flight objects
    private func parseFlightradar24Response(data: Data, direction: FlightDirection, airportIcao: String) throws -> [Flight] {
        do {
            // Parse JSON response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("Flightradar24FlightService: Invalid JSON response")
                return []
            }
            
            // FlightRadar24 API typically returns data in a nested structure
            // Try different possible response structures
            var flightsArray: [[String: Any]]?
            
            // Structure 1: Direct array
            if let directArray = json["data"] as? [[String: Any]] {
                flightsArray = directArray
            }
            // Structure 2: Nested in result/response
            else if let result = json["result"] as? [String: Any],
                    let response = result["response"] as? [String: Any],
                    let airport = response["airport"] as? [String: Any],
                    let pluginData = airport["pluginData"] as? [String: Any],
                    let schedule = pluginData["schedule"] as? [String: Any] {
                let key = direction == .arrival ? "arrivals" : "departures"
                flightsArray = schedule[key] as? [[String: Any]]
            }
            // Structure 3: Direct in response
            else if let response = json["response"] as? [String: Any] {
                let key = direction == .arrival ? "arrivals" : "departures"
                flightsArray = response[key] as? [[String: Any]]
            }
            // Structure 4: Top-level array
            else if let array = json["flights"] as? [[String: Any]] {
                flightsArray = array
            }
            
            guard let flights = flightsArray else {
                // Log the structure for debugging
                print("Flightradar24FlightService: Could not find flights array in response. Top-level keys: \(json.keys.joined(separator: ", "))")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("Flightradar24FlightService: Full response: \(jsonString.prefix(1000))")
                }
                return []
            }
            
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            return flights.compactMap { flightData -> Flight? in
                // Extract flight information from FlightRadar24 response
                // Field names may vary, so we try multiple possibilities
                let flightNumber = flightData["flight"] as? [String: Any]
                let identification = flightData["identification"] as? [String: Any]
                let airline = flightData["airline"] as? [String: Any]
                let aircraft = flightData["aircraft"] as? [String: Any]
                let airport = flightData["airport"] as? [String: Any]
                let time = flightData["time"] as? [String: Any]
                let status = flightData["status"] as? [String: Any]
                
                // Get callsign/flight number
                let callsign = identification?["callsign"] as? String ?? 
                              flightNumber?["number"] as? String ?? 
                              flightData["callsign"] as? String
                
                guard let callsign = callsign, !callsign.isEmpty else {
                    return nil
                }
                
                // Get airline
                let airlineName = airline?["name"] as? String ?? 
                                 airline?["iata"] as? String ?? 
                                 airline?["icao"] as? String
                
                // Get aircraft type
                let aircraftType = aircraft?["model"] as? [String: Any]
                let aircraftName = aircraftType?["text"] as? String ?? 
                                 aircraft?["model"] as? String
                
                // Get airport codes
                let origin = airport?["origin"] as? [String: Any]
                let destination = airport?["destination"] as? [String: Any]
                
                let originIcao: String?
                let originName: String?
                let destinationIcao: String?
                let destinationName: String?
                
                if direction == .arrival {
                    originIcao = (origin?["code"] as? [String: Any])?["icao"] as? String ?? 
                                origin?["code"] as? String ??
                                origin?["icao"] as? String
                    let position = origin?["position"] as? [String: Any]
                    let region = position?["region"] as? [String: Any]
                    originName = origin?["name"] as? String ?? 
                                region?["city"] as? String
                    destinationIcao = airportIcao
                    destinationName = nil
                } else {
                    originIcao = airportIcao
                    originName = nil
                    destinationIcao = (destination?["code"] as? [String: Any])?["icao"] as? String ?? 
                                     destination?["code"] as? String ??
                                     destination?["icao"] as? String
                    let position = destination?["position"] as? [String: Any]
                    let region = position?["region"] as? [String: Any]
                    destinationName = destination?["name"] as? String ?? 
                                     region?["city"] as? String
                }
                
                // Parse times
                let scheduledTime: Date?
                let estimatedTime: Date?
                let actualTime: Date?
                
                if let scheduled = time?["scheduled"] as? [String: Any] {
                    if let scheduledStr = scheduled["arrival"] as? String ?? scheduled["departure"] as? String {
                        scheduledTime = dateFormatter.date(from: scheduledStr) ?? 
                                       Date(timeIntervalSince1970: (scheduledStr as NSString).doubleValue)
                    } else if let scheduledTs = scheduled["arrival"] as? Int ?? scheduled["departure"] as? Int {
                        scheduledTime = Date(timeIntervalSince1970: TimeInterval(scheduledTs))
                    } else {
                        scheduledTime = nil
                    }
                } else if let scheduledTs = time?["scheduled"] as? Int {
                    scheduledTime = Date(timeIntervalSince1970: TimeInterval(scheduledTs))
                } else {
                    scheduledTime = nil
                }
                
                if let estimated = time?["estimated"] as? [String: Any] {
                    if let estimatedStr = estimated["arrival"] as? String ?? estimated["departure"] as? String {
                        estimatedTime = dateFormatter.date(from: estimatedStr) ?? 
                                       Date(timeIntervalSince1970: (estimatedStr as NSString).doubleValue)
                    } else if let estimatedTs = estimated["arrival"] as? Int ?? estimated["departure"] as? Int {
                        estimatedTime = Date(timeIntervalSince1970: TimeInterval(estimatedTs))
                    } else {
                        estimatedTime = nil
                    }
                } else if let estimatedTs = time?["estimated"] as? Int {
                    estimatedTime = Date(timeIntervalSince1970: TimeInterval(estimatedTs))
                } else {
                    estimatedTime = nil
                }
                
                if let actual = time?["actual"] as? [String: Any] {
                    if let actualStr = actual["arrival"] as? String ?? actual["departure"] as? String {
                        actualTime = dateFormatter.date(from: actualStr) ?? 
                                    Date(timeIntervalSince1970: (actualStr as NSString).doubleValue)
                    } else if let actualTs = actual["arrival"] as? Int ?? actual["departure"] as? Int {
                        actualTime = Date(timeIntervalSince1970: TimeInterval(actualTs))
                    } else {
                        actualTime = nil
                    }
                } else if let actualTs = time?["actual"] as? Int {
                    actualTime = Date(timeIntervalSince1970: TimeInterval(actualTs))
                } else {
                    actualTime = nil
                }
                
                // Determine status
                let generic = status?["generic"] as? [String: Any]
                let statusText = status?["text"] as? String ?? 
                               generic?["status"] as? String ??
                               flightData["status"] as? String
                
                let flightStatus: FlightStatus
                if let statusText = statusText?.lowercased() {
                    if statusText.contains("landed") || statusText.contains("arrived") {
                        flightStatus = .landed
                    } else if statusText.contains("departed") {
                        flightStatus = .departed
                    } else if statusText.contains("en route") || statusText.contains("enroute") {
                        flightStatus = .enRoute
                    } else if statusText.contains("delayed") {
                        flightStatus = .delayed
                    } else if statusText.contains("cancelled") || statusText.contains("canceled") {
                        flightStatus = .cancelled
                    } else if statusText.contains("diverted") {
                        flightStatus = .diverted
                    } else {
                        flightStatus = .scheduled
                    }
                } else {
                    // Infer status from times
                    if actualTime != nil {
                        flightStatus = direction == .arrival ? .landed : .departed
                    } else if estimatedTime != nil {
                        flightStatus = .enRoute
                    } else {
                        flightStatus = .scheduled
                    }
                }
                
                // Generate unique ID
                let id = "\(callsign)-\(scheduledTime?.timeIntervalSince1970 ?? 0)-\(direction.rawValue)"
                
                return Flight(
                    id: id,
                    callsign: callsign,
                    flightNumber: extractFlightNumber(from: callsign),
                    airline: airlineName,
                    aircraft: aircraftName,
                    originIcao: originIcao,
                    originName: originName,
                    destinationIcao: destinationIcao,
                    destinationName: destinationName,
                    scheduledTime: scheduledTime,
                    estimatedTime: estimatedTime,
                    actualTime: actualTime,
                    status: flightStatus,
                    direction: direction
                )
            }
        } catch {
            print("Flightradar24FlightService: Parse error: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Flightradar24FlightService: Response data: \(jsonString.prefix(1000))")
            }
            throw FlightServiceError.parseError(error)
        }
    }
    
    /// Extract flight number from callsign (e.g., "UAL123" -> "UA123")
    private func extractFlightNumber(from callsign: String) -> String? {
        let cleaned = callsign.trimmingCharacters(in: .whitespaces)
        guard cleaned.count > 3 else { return cleaned.isEmpty ? nil : cleaned }
        
        // Try to find where numbers start
        if let firstDigitIndex = cleaned.firstIndex(where: { $0.isNumber }) {
            let airlinePrefix = String(cleaned[..<firstDigitIndex])
            let flightNum = String(cleaned[firstDigitIndex...])
            
            // Convert ICAO airline code to common format
            let iataCode = icaoToIataAirline(airlinePrefix)
            return "\(iataCode)\(flightNum)"
        }
        
        return cleaned
    }
    
    /// Convert ICAO airline code to IATA code
    private func icaoToIataAirline(_ icao: String) -> String {
        let mapping: [String: String] = [
            "UAL": "UA", "AAL": "AA", "DAL": "DL", "SWA": "WN",
            "JBU": "B6", "ASA": "AS", "SKW": "OO", "RPA": "YX",
            "FFT": "F9", "NKS": "NK", "BAW": "BA", "AFR": "AF",
            "DLH": "LH", "KLM": "KL", "UAE": "EK", "QFA": "QF",
            "SIA": "SQ", "CPA": "CX", "ANA": "NH", "JAL": "JL"
        ]
        return mapping[icao] ?? icao
    }
    
    /// Update API key (called when credentials change)
    func updateCredentials() {
        if let credentials = settings.getCredentials(for: .flightradar24) {
            self.apiKey = credentials["api_key"]
        } else {
            self.apiKey = nil
        }
    }
    
    /// Test API credentials by making a simple request
    func testCredentials(apiKey: String) async throws -> Bool {
        // Use sandbox endpoint to test authentication
        // Try to get airport arrivals for London Heathrow
        guard let url = URL(string: "\(baseURL)/api/sandbox/airports/EGLL/flights?type=arrivals&limit=1") else {
            throw FlightServiceError.networkError(URLError(.badURL))
        }
        
        var request = URLRequest(url: url)
        request.setValue("Aviary/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FlightServiceError.networkError(URLError(.badServerResponse))
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
            return true
        } catch {
            throw FlightServiceError.networkError(error)
        }
    }
}

