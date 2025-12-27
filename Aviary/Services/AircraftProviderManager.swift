//
//  AircraftProviderManager.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import CoreLocation

/// Manages aircraft data providers and handles provider switching
final class AircraftProviderManager {
    static let shared = AircraftProviderManager()
    
    private var currentProvider: AircraftDataProvider?
    private let settings = AircraftSettings.shared
    
    private init() {
        loadProvider()
    }
    
    /// Get the current provider
    var provider: AircraftDataProvider {
        if let current = currentProvider {
            return current
        }
        // Default to OpenSky anonymous
        let provider = OpenSkyAircraftProvider(authenticated: false)
        currentProvider = provider
        return provider
    }
    
    /// Load provider based on settings
    func loadProvider() {
        let providerType = settings.selectedProvider
        
        switch providerType {
        case .openSky:
            currentProvider = OpenSkyAircraftProvider(authenticated: false)
            
        case .openSkyAuthenticated:
            let provider = OpenSkyAircraftProvider(authenticated: true)
            if let credentials = settings.getCredentials(for: .openSkyAuthenticated) {
                try? provider.configureAuth(credentials: credentials)
            }
            currentProvider = provider
            
        case .flightradar24:
            let provider = Flightradar24AircraftProvider()
            if let credentials = settings.getCredentials(for: .flightradar24) {
                try? provider.configureAuth(credentials: credentials)
            }
            currentProvider = provider
            
            // Automatically sync flight service to FlightRadar24
            let flightSettings = FlightServiceSettings.shared
            if flightSettings.selectedService != .flightradar24 {
                flightSettings.selectedService = .flightradar24
                Flightradar24FlightService.shared.updateCredentials()
                NotificationCenter.default.post(name: .flightServiceChanged, object: nil)
            }
            
        case .aviationstack:
            let provider = AviationstackAircraftProvider()
            if let credentials = settings.getCredentials(for: .aviationstack) {
                try? provider.configureAuth(credentials: credentials)
            }
            currentProvider = provider
        }
    }
    
    /// Switch to a new provider
    func switchProvider(to type: AircraftProviderType, credentials: [String: String]? = nil) throws {
        let newProvider: AircraftDataProvider
        
        switch type {
        case .openSky:
            newProvider = OpenSkyAircraftProvider(authenticated: false)
            
        case .openSkyAuthenticated:
            let provider = OpenSkyAircraftProvider(authenticated: true)
            if let credentials = credentials {
                try provider.configureAuth(credentials: credentials)
            }
            newProvider = provider
            
        case .flightradar24:
            let provider = Flightradar24AircraftProvider()
            if let credentials = credentials {
                try provider.configureAuth(credentials: credentials)
            }
            newProvider = provider
            
        case .aviationstack:
            let provider = AviationstackAircraftProvider()
            if let credentials = credentials {
                try provider.configureAuth(credentials: credentials)
            }
            newProvider = provider
        }
        
        currentProvider = newProvider
        settings.selectedProvider = type
        if let credentials = credentials {
            settings.saveCredentials(credentials, for: type)
        }
        
        // If FlightRadar24 is selected for aircraft, automatically use it for flights too
        if type == .flightradar24 {
            let flightSettings = FlightServiceSettings.shared
            if flightSettings.selectedService != .flightradar24 {
                flightSettings.selectedService = .flightradar24
                // Update flight service credentials
                Flightradar24FlightService.shared.updateCredentials()
                NotificationCenter.default.post(name: .flightServiceChanged, object: nil)
            }
        }
    }
    
    /// Update credentials for current provider
    func updateCredentials(_ credentials: [String: String]) throws {
        guard let provider = currentProvider else {
            throw AircraftProviderError.missingCredentials
        }
        
        try provider.configureAuth(credentials: credentials)
        settings.saveCredentials(credentials, for: settings.selectedProvider)
    }
}

