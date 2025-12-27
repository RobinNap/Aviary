//
//  OpenSkyFlightService.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation

/// Flight service implementation using OpenSky Network API
/// API Documentation: https://openskynetwork.github.io/opensky-api/rest.html
final class OpenSkyFlightService: FlightService {
    static let shared = OpenSkyFlightService()
    
    private let baseURL = "https://opensky-network.org/api"
    private let authURL = "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token"
    private let session: URLSession
    private let decoder: JSONDecoder
    
    // Rate limiting with exponential backoff
    private var lastRequestTime: Date?
    private var consecutiveFailures: Int = 0
    private var minRequestInterval: TimeInterval = 10 // Default for anonymous
    private let maxBackoffInterval: TimeInterval = 300 // Max 5 minutes backoff
    
    // Authentication credentials
    private var credentials: [String: String]?
    private var accessToken: String?
    private var tokenExpiry: Date?
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }
    
    /// Configure authentication for faster rate limits
    /// Supports both OAuth2 (clientId/clientSecret) and legacy (username/password)
    func configureAuth(clientId: String? = nil, clientSecret: String? = nil, username: String? = nil, password: String? = nil) {
        if let clientId = clientId, let clientSecret = clientSecret, !clientId.isEmpty && !clientSecret.isEmpty {
            // OAuth2 credentials
            self.credentials = ["clientId": clientId, "clientSecret": clientSecret]
        } else if let username = username, let password = password, !username.isEmpty && !password.isEmpty {
            // Legacy Basic Auth credentials
            self.credentials = ["username": username, "password": password]
        }
        self.minRequestInterval = 1.0 // Authenticated users get 1 request/second
        // Clear any existing token when credentials change
        self.accessToken = nil
        self.tokenExpiry = nil
    }
    
    /// Clear authentication (revert to anonymous)
    func clearAuth() {
        self.credentials = nil
        self.accessToken = nil
        self.tokenExpiry = nil
        self.minRequestInterval = 10.0
    }
    
    /// Get OAuth2 access token using client credentials flow
    private func getAccessToken() async throws -> String {
        // Check if we have a valid cached token
        if let token = accessToken,
           let expiry = tokenExpiry,
           expiry > Date() {
            return token
        }
        
        guard let creds = credentials,
              let clientId = creds["clientId"],
              let clientSecret = creds["clientSecret"],
              !clientId.isEmpty && !clientSecret.isEmpty else {
            throw FlightServiceError.networkError(URLError(.userAuthenticationRequired))
        }
        
        guard let url = URL(string: authURL) else {
            throw FlightServiceError.networkError(URLError(.badURL))
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
        
        print("OpenSkyFlightService: Requesting OAuth2 access token")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FlightServiceError.networkError(URLError(.badServerResponse))
            }
            
            if httpResponse.statusCode == 200 {
                // Parse token response
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let token = json["access_token"] as? String else {
                    throw FlightServiceError.parseError(NSError(domain: "OpenSky", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse token response"]))
                }
                
                // Get token expiry (default to 1 hour if not provided)
                let expiresIn = json["expires_in"] as? Int ?? 3600
                self.accessToken = token
                self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn - 60)) // Refresh 1 minute before expiry
                
                print("OpenSkyFlightService: Successfully obtained access token")
                return token
            } else {
                print("OpenSkyFlightService: Failed to get access token, status: \(httpResponse.statusCode)")
                throw FlightServiceError.networkError(URLError(.userAuthenticationRequired))
            }
        } catch {
            throw FlightServiceError.networkError(error)
        }
    }
    
    /// Fetch arrivals for an airport
    /// Uses OpenSky API: GET /flights/arrival?airport={icao}&begin={unix}&end={unix}
    func fetchFlights(
        airportIcao: String,
        direction: FlightDirection,
        from: Date,
        to: Date
    ) async throws -> [Flight] {
        // Validate ICAO code
        guard airportIcao.count >= 3 && airportIcao.count <= 4 else {
            throw FlightServiceError.invalidAirportCode
        }
        
        // OpenSky limitation: time interval must not be larger than 7 days for arrivals/departures
        let maxInterval: TimeInterval = 7 * 24 * 60 * 60
        let interval = to.timeIntervalSince(from)
        if interval > maxInterval {
            throw FlightServiceError.networkError(URLError(.badURL))
        }
        
        // Rate limiting check with exponential backoff
        if let lastRequest = lastRequestTime {
            let baseInterval = minRequestInterval
            let backoffMultiplier = pow(2.0, Double(min(consecutiveFailures, 5))) // Cap at 2^5 = 32x
            let requiredInterval = baseInterval * backoffMultiplier
            let maxInterval = min(requiredInterval, maxBackoffInterval)
            
            let elapsed = Date().timeIntervalSince(lastRequest)
            if elapsed < maxInterval {
                let waitTime = maxInterval - elapsed
                print("OpenSkyFlightService: Rate limiting - waiting \(waitTime) seconds (failures: \(consecutiveFailures))")
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
        
        lastRequestTime = Date()
        
        // Build URL based on direction
        // Arrivals: GET /flights/arrival?airport={icao}&begin={unix}&end={unix}
        // Departures: GET /flights/departure?airport={icao}&begin={unix}&end={unix}
        let endpoint = direction == .arrival ? "flights/arrival" : "flights/departure"
        let beginTimestamp = Int(from.timeIntervalSince1970)
        let endTimestamp = Int(to.timeIntervalSince1970)
        
        guard var urlComponents = URLComponents(string: "\(baseURL)/\(endpoint)") else {
            throw FlightServiceError.networkError(URLError(.badURL))
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "airport", value: airportIcao.uppercased()),
            URLQueryItem(name: "begin", value: String(beginTimestamp)),
            URLQueryItem(name: "end", value: String(endTimestamp))
        ]
        
        guard let url = urlComponents.url else {
            throw FlightServiceError.networkError(URLError(.badURL))
        }
        
        // Make request
        do {
            var request = URLRequest(url: url)
            request.setValue("Aviary/1.0", forHTTPHeaderField: "User-Agent")
            
            // Add authentication if configured
            // For anonymous mode, do NOT send any Authorization header
            if let creds = credentials {
                // Try OAuth2 first (clientId/clientSecret)
                if let clientId = creds["clientId"],
                   let clientSecret = creds["clientSecret"],
                   !clientId.isEmpty && !clientSecret.isEmpty {
                    // Get OAuth2 access token
                    do {
                        let token = try await getAccessToken()
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        print("OpenSkyFlightService: Using OAuth2 authenticated mode")
                    } catch {
                        print("OpenSkyFlightService: Failed to get OAuth2 token: \(error)")
                        throw error
                    }
                }
                // Fallback to legacy Basic Auth (username/password)
                else if let username = creds["username"],
                        let password = creds["password"],
                        !username.isEmpty && !password.isEmpty {
                    let authString = "\(username):\(password)"
                    if let authData = authString.data(using: .utf8) {
                        let base64Auth = authData.base64EncodedString()
                        request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
                        print("OpenSkyFlightService: Using Basic Auth (legacy)")
                    }
                }
            } else {
                print("OpenSkyFlightService: Using anonymous mode (no authentication)")
            }
            
            print("OpenSkyFlightService: Fetching \(direction) for \(airportIcao) from \(url)")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FlightServiceError.networkError(URLError(.badServerResponse))
            }
            
            print("OpenSkyFlightService: Response status \(httpResponse.statusCode)")
            
            switch httpResponse.statusCode {
            case 200:
                consecutiveFailures = 0 // Reset on success
                return try parseOpenSkyResponse(data: data, direction: direction, airportIcao: airportIcao)
            case 401:
                consecutiveFailures += 1
                if credentials != nil {
                    print("OpenSkyFlightService: Authentication failed (401) - check credentials")
                } else {
                    print("OpenSkyFlightService: Unexpected 401 in anonymous mode - API may be blocking requests")
                }
                // Try to parse error message if available
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = errorJson["message"] as? String {
                    print("OpenSkyFlightService: API error: \(message)")
                }
                throw FlightServiceError.networkError(URLError(.userAuthenticationRequired))
            case 429:
                consecutiveFailures += 1
                print("OpenSkyFlightService: Rate limited (429) - consecutive failures: \(consecutiveFailures)")
                throw FlightServiceError.rateLimited
            case 404:
                consecutiveFailures = 0 // Not a failure, just no data
                // Log response body if available to help debug
                if let responseString = String(data: data, encoding: .utf8), !responseString.isEmpty {
                    print("OpenSkyFlightService: No data found (404) for \(direction) at airport \(airportIcao), response: \(responseString)")
                } else {
                    let timeRange = "\(beginTimestamp) (\(Date(timeIntervalSince1970: TimeInterval(beginTimestamp)))) to \(endTimestamp) (\(Date(timeIntervalSince1970: TimeInterval(endTimestamp))))"
                    print("OpenSkyFlightService: No data found (404) for \(direction) at airport \(airportIcao) in time range: \(timeRange)")
                }
                // For arrivals, 404 is common due to batch processing delays
                // Return empty array - the view model will try fallback ranges
                return [] // No data for this airport/time range
            default:
                consecutiveFailures += 1
                print("OpenSkyFlightService: Unexpected status code \(httpResponse.statusCode)")
                throw FlightServiceError.networkError(URLError(.badServerResponse))
            }
        } catch let error as FlightServiceError {
            throw error
        } catch {
            throw FlightServiceError.networkError(error)
        }
    }
    
    /// Parse OpenSky API response into Flight objects
    /// Response is a JSON array of flight objects
    private func parseOpenSkyResponse(data: Data, direction: FlightDirection, airportIcao: String) throws -> [Flight] {
        do {
            let openSkyFlights = try decoder.decode([OpenSkyFlight].self, from: data)
            let normalizedAirportIcao = airportIcao.uppercased()
            
            print("OpenSkyFlightService: Parsing \(openSkyFlights.count) flights")
            
            return openSkyFlights.compactMap { osFlight -> Flight? in
                // Skip entries without essential data
                guard let callsign = osFlight.callsign?.trimmingCharacters(in: .whitespaces),
                      !callsign.isEmpty else {
                    return nil
                }
                
                // Verify flight matches the requested airport
                let matchesAirport: Bool
                if direction == .arrival {
                    matchesAirport = osFlight.estArrivalAirport?.uppercased() == normalizedAirportIcao
                } else {
                    matchesAirport = osFlight.estDepartureAirport?.uppercased() == normalizedAirportIcao
                }
                
                guard matchesAirport else {
                    return nil
                }
                
                // Determine times and status
                let now = Date()
                let scheduledTime: Date?
                let actualTime: Date?
                let estimatedTime: Date?
                let status: FlightStatus
                
                if direction == .arrival {
                    // For arrivals, lastSeen is when aircraft was last tracked (likely landed)
                    if let lastSeen = osFlight.lastSeen {
                        let lastSeenDate = Date(timeIntervalSince1970: TimeInterval(lastSeen))
                        actualTime = lastSeenDate
                        scheduledTime = lastSeenDate
                        status = .landed
                        estimatedTime = nil
                    } else if let firstSeen = osFlight.firstSeen {
                        // Aircraft is being tracked but hasn't landed yet
                        let firstSeenDate = Date(timeIntervalSince1970: TimeInterval(firstSeen))
                        scheduledTime = firstSeenDate
                        estimatedTime = now.addingTimeInterval(1800) // Estimate 30 min from now
                        actualTime = nil
                        status = .enRoute
                    } else {
                        scheduledTime = nil
                        estimatedTime = nil
                        actualTime = nil
                        status = .scheduled
                    }
                } else {
                    // For departures, firstSeen is when aircraft was first tracked (likely departed)
                    if let firstSeen = osFlight.firstSeen {
                        let firstSeenDate = Date(timeIntervalSince1970: TimeInterval(firstSeen))
                        actualTime = firstSeenDate
                        scheduledTime = firstSeenDate
                        status = .departed
                        estimatedTime = nil
                    } else {
                        // Scheduled but not yet departed
                        scheduledTime = now.addingTimeInterval(3600) // Default to 1 hour from now
                        estimatedTime = scheduledTime
                        actualTime = nil
                        status = .scheduled
                    }
                }
                
                return Flight(
                    id: "\(osFlight.icao24)-\(osFlight.firstSeen ?? 0)-\(osFlight.lastSeen ?? 0)",
                    callsign: callsign,
                    flightNumber: extractFlightNumber(from: callsign),
                    airline: extractAirline(from: callsign),
                    aircraft: nil,
                    originIcao: osFlight.estDepartureAirport,
                    originName: nil,
                    destinationIcao: osFlight.estArrivalAirport,
                    destinationName: nil,
                    scheduledTime: scheduledTime,
                    estimatedTime: estimatedTime,
                    actualTime: actualTime,
                    status: status,
                    direction: direction
                )
            }
        } catch {
            print("OpenSkyFlightService: Parse error: \(error)")
            throw FlightServiceError.parseError(error)
        }
    }
    
    /// Extract flight number from callsign (e.g., "UAL123" -> "UA123")
    private func extractFlightNumber(from callsign: String) -> String? {
        let cleaned = callsign.trimmingCharacters(in: .whitespaces)
        guard cleaned.count > 3 else { return nil }
        
        // Find where numbers start
        if let firstDigitIndex = cleaned.firstIndex(where: { $0.isNumber }) {
            let airlinePrefix = String(cleaned[..<firstDigitIndex])
            let flightNum = String(cleaned[firstDigitIndex...])
            
            // Convert ICAO airline code to IATA
            let iataCode = icaoToIataAirline(airlinePrefix)
            return "\(iataCode)\(flightNum)"
        }
        
        return nil
    }
    
    /// Extract airline name from callsign
    private func extractAirline(from callsign: String) -> String? {
        let cleaned = callsign.trimmingCharacters(in: .whitespaces)
        guard cleaned.count >= 3 else { return nil }
        
        // Get the airline code prefix
        var airlineCode = ""
        for char in cleaned {
            if char.isNumber { break }
            airlineCode.append(char)
        }
        
        return airlineNames[airlineCode]
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
    
    /// Airline names mapping
    private let airlineNames: [String: String] = [
        "UAL": "United Airlines",
        "AAL": "American Airlines",
        "DAL": "Delta Air Lines",
        "SWA": "Southwest Airlines",
        "JBU": "JetBlue Airways",
        "ASA": "Alaska Airlines",
        "SKW": "SkyWest Airlines",
        "RPA": "Republic Airways",
        "FFT": "Frontier Airlines",
        "NKS": "Spirit Airlines",
        "BAW": "British Airways",
        "AFR": "Air France",
        "DLH": "Lufthansa",
        "KLM": "KLM Royal Dutch Airlines",
        "UAE": "Emirates",
        "QFA": "Qantas",
        "SIA": "Singapore Airlines",
        "CPA": "Cathay Pacific",
        "ANA": "All Nippon Airways",
        "JAL": "Japan Airlines"
    ]
}

// MARK: - OpenSky API Response Models
private struct OpenSkyFlight: Codable {
    let icao24: String
    let firstSeen: Int?
    let estDepartureAirport: String?
    let lastSeen: Int?
    let estArrivalAirport: String?
    let callsign: String?
    let estDepartureAirportHorizDistance: Int?
    let estDepartureAirportVertDistance: Int?
    let estArrivalAirportHorizDistance: Int?
    let estArrivalAirportVertDistance: Int?
    let departureAirportCandidatesCount: Int?
    let arrivalAirportCandidatesCount: Int?
}
