//
//  OpenSkyFlightService.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation

/// Flight service implementation using OpenSky Network API
/// API Documentation: https://openskynetwork.github.io/opensky-api/
final class OpenSkyFlightService: FlightService {
    static let shared = OpenSkyFlightService()
    
    private let baseURL = "https://opensky-network.org/api"
    private let session: URLSession
    private let decoder: JSONDecoder
    
    // Rate limiting
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 10 // 10 seconds between requests
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        
        self.decoder = JSONDecoder()
    }
    
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
        
        // Rate limiting check
        if let lastRequest = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastRequest)
            if elapsed < minRequestInterval {
                let waitTime = minRequestInterval - elapsed
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
        
        lastRequestTime = Date()
        
        // Build URL
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
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FlightServiceError.networkError(URLError(.badServerResponse))
            }
            
            switch httpResponse.statusCode {
            case 200:
                return try parseOpenSkyResponse(data: data, direction: direction, airportIcao: airportIcao)
            case 429:
                throw FlightServiceError.rateLimited
            case 404:
                return [] // No data for this airport
            default:
                throw FlightServiceError.networkError(URLError(.badServerResponse))
            }
        } catch let error as FlightServiceError {
            throw error
        } catch {
            throw FlightServiceError.networkError(error)
        }
    }
    
    /// Parse OpenSky API response into Flight objects
    private func parseOpenSkyResponse(data: Data, direction: FlightDirection, airportIcao: String) throws -> [Flight] {
        do {
            let openSkyFlights = try decoder.decode([OpenSkyFlight].self, from: data)
            
            return openSkyFlights.compactMap { osFlight -> Flight? in
                // Skip entries without essential data
                guard let callsign = osFlight.callsign?.trimmingCharacters(in: .whitespaces),
                      !callsign.isEmpty else {
                    return nil
                }
                
                let scheduledTime: Date?
                let actualTime: Date?
                let status: FlightStatus
                
                if direction == .arrival {
                    scheduledTime = osFlight.lastSeen.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    actualTime = scheduledTime
                    status = actualTime != nil ? .landed : .scheduled
                } else {
                    scheduledTime = osFlight.firstSeen.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    actualTime = scheduledTime
                    status = actualTime != nil ? .departed : .scheduled
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
                    estimatedTime: nil,
                    actualTime: actualTime,
                    status: status,
                    direction: direction
                )
            }
        } catch {
            throw FlightServiceError.parseError(error)
        }
    }
    
    /// Extract flight number from callsign (e.g., "UAL123" -> "UA123")
    private func extractFlightNumber(from callsign: String) -> String? {
        // Simple extraction - first 3 letters are airline code, rest is flight number
        let cleaned = callsign.trimmingCharacters(in: .whitespaces)
        guard cleaned.count > 3 else { return nil }
        
        // Try to find where numbers start
        if let firstDigitIndex = cleaned.firstIndex(where: { $0.isNumber }) {
            let airlinePrefix = String(cleaned[..<firstDigitIndex])
            let flightNum = String(cleaned[firstDigitIndex...])
            
            // Convert ICAO airline code to common format
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

