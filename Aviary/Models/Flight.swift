//
//  Flight.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation

/// Direction of flight relative to an airport
enum FlightDirection: String, Codable, CaseIterable {
    case arrival
    case departure
}

/// Flight status
enum FlightStatus: String, Codable, CaseIterable {
    case scheduled
    case enRoute
    case landed
    case departed
    case delayed
    case cancelled
    case diverted
    case unknown
    
    var displayName: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .enRoute: return "En Route"
        case .landed: return "Landed"
        case .departed: return "Departed"
        case .delayed: return "Delayed"
        case .cancelled: return "Cancelled"
        case .diverted: return "Diverted"
        case .unknown: return "Unknown"
        }
    }
    
    var iconName: String {
        switch self {
        case .scheduled: return "clock"
        case .enRoute: return "airplane"
        case .landed: return "airplane.arrival"
        case .departed: return "airplane.departure"
        case .delayed: return "clock.badge.exclamationmark"
        case .cancelled: return "xmark.circle"
        case .diverted: return "arrow.triangle.branch"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Represents a flight arrival or departure
struct Flight: Identifiable, Codable, Hashable {
    let id: String
    let callsign: String?
    let flightNumber: String?
    let airline: String?
    let aircraft: String?
    let originIcao: String?
    let originName: String?
    let destinationIcao: String?
    let destinationName: String?
    let scheduledTime: Date?
    let estimatedTime: Date?
    let actualTime: Date?
    let status: FlightStatus
    let direction: FlightDirection
    
    /// The most relevant time to display
    var displayTime: Date? {
        actualTime ?? estimatedTime ?? scheduledTime
    }
    
    /// The other airport (origin for arrivals, destination for departures)
    var otherAirportCode: String? {
        switch direction {
        case .arrival: return originIcao
        case .departure: return destinationIcao
        }
    }
    
    var otherAirportName: String? {
        switch direction {
        case .arrival: return originName
        case .departure: return destinationName
        }
    }
    
    /// Display identifier (flight number or callsign)
    var displayIdentifier: String {
        flightNumber ?? callsign ?? id
    }
}

// MARK: - Sample Data for Previews
extension Flight {
    static let sampleArrival = Flight(
        id: "arr-001",
        callsign: "UAL123",
        flightNumber: "UA123",
        airline: "United Airlines",
        aircraft: "Boeing 737-800",
        originIcao: "KSFO",
        originName: "San Francisco Intl",
        destinationIcao: "KLAX",
        destinationName: "Los Angeles Intl",
        scheduledTime: Date().addingTimeInterval(-3600),
        estimatedTime: Date().addingTimeInterval(-1800),
        actualTime: Date().addingTimeInterval(-900),
        status: .landed,
        direction: .arrival
    )
    
    static let sampleDeparture = Flight(
        id: "dep-001",
        callsign: "AAL456",
        flightNumber: "AA456",
        airline: "American Airlines",
        aircraft: "Airbus A321",
        originIcao: "KLAX",
        originName: "Los Angeles Intl",
        destinationIcao: "KJFK",
        destinationName: "John F. Kennedy Intl",
        scheduledTime: Date().addingTimeInterval(3600),
        estimatedTime: Date().addingTimeInterval(3900),
        actualTime: nil,
        status: .scheduled,
        direction: .departure
    )
    
    static let sampleArrivals: [Flight] = [
        sampleArrival,
        Flight(
            id: "arr-002",
            callsign: "DAL789",
            flightNumber: "DL789",
            airline: "Delta Air Lines",
            aircraft: "Boeing 757-200",
            originIcao: "KATL",
            originName: "Atlanta Intl",
            destinationIcao: "KLAX",
            destinationName: "Los Angeles Intl",
            scheduledTime: Date().addingTimeInterval(1800),
            estimatedTime: Date().addingTimeInterval(2100),
            actualTime: nil,
            status: .enRoute,
            direction: .arrival
        ),
        Flight(
            id: "arr-003",
            callsign: "SWA321",
            flightNumber: "WN321",
            airline: "Southwest Airlines",
            aircraft: "Boeing 737 MAX 8",
            originIcao: "KPHX",
            originName: "Phoenix Sky Harbor",
            destinationIcao: "KLAX",
            destinationName: "Los Angeles Intl",
            scheduledTime: Date().addingTimeInterval(7200),
            estimatedTime: nil,
            actualTime: nil,
            status: .scheduled,
            direction: .arrival
        )
    ]
    
    static let sampleDepartures: [Flight] = [
        sampleDeparture,
        Flight(
            id: "dep-002",
            callsign: "UAL999",
            flightNumber: "UA999",
            airline: "United Airlines",
            aircraft: "Boeing 787-9",
            originIcao: "KLAX",
            originName: "Los Angeles Intl",
            destinationIcao: "EGLL",
            destinationName: "London Heathrow",
            scheduledTime: Date().addingTimeInterval(-300),
            estimatedTime: Date().addingTimeInterval(600),
            actualTime: nil,
            status: .delayed,
            direction: .departure
        )
    ]
}









