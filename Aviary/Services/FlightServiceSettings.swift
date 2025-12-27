//
//  FlightServiceSettings.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation

/// Manages flight data service settings
final class FlightServiceSettings {
    static let shared = FlightServiceSettings()
    
    private let userDefaults = UserDefaults.standard
    private let selectedServiceKey = "flight.selectedService"
    
    private init() {}
    
    /// Currently selected flight service
    var selectedService: FlightServiceType {
        get {
            if let rawValue = userDefaults.string(forKey: selectedServiceKey),
               let service = FlightServiceType(rawValue: rawValue) {
                return service
            }
            return .openSky // Default
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: selectedServiceKey)
        }
    }
}

/// Supported flight data services
enum FlightServiceType: String, CaseIterable, Identifiable {
    case openSky = "opensky"
    case flightradar24 = "flightradar24"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .openSky:
            return "OpenSky Network"
        case .flightradar24:
            return "Flightradar24"
        }
    }
    
    var description: String {
        switch self {
        case .openSky:
            return "Free, 1 request per 10 seconds (anonymous) or 1 per second (authenticated)"
        case .flightradar24:
            return "Paid subscription, near real-time data (requires API key)"
        }
    }
    
    var requiresAuth: Bool {
        switch self {
        case .openSky:
            return false
        case .flightradar24:
            return true
        }
    }
    
    /// Get the FlightService instance for this type
    func createService() -> FlightService {
        switch self {
        case .openSky:
            return OpenSkyFlightService.shared
        case .flightradar24:
            return Flightradar24FlightService.shared
        }
    }
}

