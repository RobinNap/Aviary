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
            // Anonymous mode - ensure no credentials are used
            currentProvider = OpenSkyAircraftProvider(authenticated: false)
            OpenSkyFlightService.shared.clearAuth()
            // Clear any stored credentials for anonymous mode (shouldn't have any, but be safe)
            settings.clearCredentials(for: .openSky)
            
        case .openSkyAuthenticated:
            let provider = OpenSkyAircraftProvider(authenticated: true)
            if let credentials = settings.getCredentials(for: .openSkyAuthenticated) {
                // Check for OAuth2 credentials (clientId/clientSecret) or legacy (username/password)
                let hasOAuth2 = !(credentials["clientId"]?.isEmpty ?? true) && !(credentials["clientSecret"]?.isEmpty ?? true)
                let hasLegacy = !(credentials["username"]?.isEmpty ?? true) && !(credentials["password"]?.isEmpty ?? true)
                
                if hasOAuth2 || hasLegacy {
                    // Only configure if credentials are valid
                    try? provider.configureAuth(credentials: credentials)
                    // Also configure flight service with same credentials
                    if hasOAuth2, let clientId = credentials["clientId"], let clientSecret = credentials["clientSecret"] {
                        OpenSkyFlightService.shared.configureAuth(clientId: clientId, clientSecret: clientSecret)
                    } else if hasLegacy, let username = credentials["username"], let password = credentials["password"] {
                        OpenSkyFlightService.shared.configureAuth(username: username, password: password)
                    }
                } else {
                    print("AircraftProviderManager: Authenticated mode selected but no valid credentials found")
                }
            } else {
                print("AircraftProviderManager: Authenticated mode selected but no credentials found")
            }
            currentProvider = provider
        }
    }
    
    /// Switch to a new provider
    func switchProvider(to type: AircraftProviderType, credentials: [String: String]? = nil) throws {
        let newProvider: AircraftDataProvider
        
        switch type {
        case .openSky:
            // Anonymous mode - ensure no credentials are used
            newProvider = OpenSkyAircraftProvider(authenticated: false)
            OpenSkyFlightService.shared.clearAuth()
            // Clear any stored credentials for anonymous mode
            settings.clearCredentials(for: .openSky)
            
        case .openSkyAuthenticated:
            let provider = OpenSkyAircraftProvider(authenticated: true)
            if let credentials = credentials {
                // Check for OAuth2 credentials (clientId/clientSecret) or legacy (username/password)
                let hasOAuth2 = !(credentials["clientId"]?.isEmpty ?? true) && !(credentials["clientSecret"]?.isEmpty ?? true)
                let hasLegacy = !(credentials["username"]?.isEmpty ?? true) && !(credentials["password"]?.isEmpty ?? true)
                
                if hasOAuth2 || hasLegacy {
                    // Only configure if credentials are valid
                    try provider.configureAuth(credentials: credentials)
                    // Also configure flight service with same credentials
                    if hasOAuth2, let clientId = credentials["clientId"], let clientSecret = credentials["clientSecret"] {
                        OpenSkyFlightService.shared.configureAuth(clientId: clientId, clientSecret: clientSecret)
                    } else if hasLegacy, let username = credentials["username"], let password = credentials["password"] {
                        OpenSkyFlightService.shared.configureAuth(username: username, password: password)
                    }
                } else {
                    print("AircraftProviderManager: Authenticated mode selected but credentials are invalid")
                }
            } else {
                print("AircraftProviderManager: Authenticated mode selected but no credentials provided")
            }
            newProvider = provider
        }
        
        currentProvider = newProvider
        settings.selectedProvider = type
        if let credentials = credentials {
            settings.saveCredentials(credentials, for: type)
        }
    }
    
    /// Update credentials for current provider
    func updateCredentials(_ credentials: [String: String]) throws {
        guard let provider = currentProvider else {
            throw AircraftProviderError.missingCredentials
        }
        
        try provider.configureAuth(credentials: credentials)
        settings.saveCredentials(credentials, for: settings.selectedProvider)
        
        // Also update flight service if authenticated
        if settings.selectedProvider == .openSkyAuthenticated {
            // Check for OAuth2 credentials (clientId/clientSecret) or legacy (username/password)
            if let clientId = credentials["clientId"],
               let clientSecret = credentials["clientSecret"],
               !clientId.isEmpty && !clientSecret.isEmpty {
                OpenSkyFlightService.shared.configureAuth(clientId: clientId, clientSecret: clientSecret)
            } else if let username = credentials["username"],
                      let password = credentials["password"],
                      !username.isEmpty && !password.isEmpty {
                OpenSkyFlightService.shared.configureAuth(username: username, password: password)
            }
        }
    }
}
