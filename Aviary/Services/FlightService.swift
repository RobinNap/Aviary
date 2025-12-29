//
//  FlightService.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation

/// Protocol defining flight data service operations
protocol FlightService {
    /// Fetch flights for an airport within a time range
    func fetchFlights(
        airportIcao: String,
        direction: FlightDirection,
        from: Date,
        to: Date
    ) async throws -> [Flight]
}

/// Errors that can occur during flight data operations
enum FlightServiceError: LocalizedError {
    case invalidAirportCode
    case networkError(Error)
    case rateLimited
    case parseError(Error)
    case noData
    
    var errorDescription: String? {
        switch self {
        case .invalidAirportCode:
            return "Invalid airport code"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .parseError(let error):
            return "Failed to parse data: \(error.localizedDescription)"
        case .noData:
            return "No flight data available"
        }
    }
}


