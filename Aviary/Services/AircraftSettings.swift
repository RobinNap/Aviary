//
//  AircraftSettings.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation

/// UI Mode for the app
enum UIMode: String, CaseIterable {
    case simplified
    case pro
    
    var displayName: String {
        switch self {
        case .simplified: return "Simplified"
        case .pro: return "Pro"
        }
    }
    
    var description: String {
        switch self {
        case .simplified: return "Clean interface with floating ATC player. No side panel or plane details."
        case .pro: return "Full-featured interface with side panel, weather, and plane details."
        }
    }
}

/// Manages aircraft data provider settings
final class AircraftSettings {
    static let shared = AircraftSettings()
    
    private let userDefaults = UserDefaults.standard
    private let selectedProviderKey = "aircraft.selectedProvider"
    private let credentialsKeyPrefix = "aircraft.credentials."
    private let uiModeKey = "app.uiMode"
    
    private init() {}
    
    /// Currently selected provider
    var selectedProvider: AircraftProviderType {
        get {
            if let rawValue = userDefaults.string(forKey: selectedProviderKey),
               let provider = AircraftProviderType(rawValue: rawValue) {
                return provider
            }
            return .openSky // Default
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: selectedProviderKey)
        }
    }
    
    /// Current UI mode
    var uiMode: UIMode {
        get {
            if let rawValue = userDefaults.string(forKey: uiModeKey),
               let mode = UIMode(rawValue: rawValue) {
                return mode
            }
            return .pro // Default to Pro
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: uiModeKey)
        }
    }
    
    /// Save credentials for a provider
    func saveCredentials(_ credentials: [String: String], for provider: AircraftProviderType) {
        // Store credentials securely (in production, use Keychain)
        let key = "\(credentialsKeyPrefix)\(provider.rawValue)"
        
        // For now, store as JSON string (in production, use Keychain)
        if let jsonData = try? JSONSerialization.data(withJSONObject: credentials),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            userDefaults.set(jsonString, forKey: key)
        }
    }
    
    /// Get credentials for a provider
    func getCredentials(for provider: AircraftProviderType) -> [String: String]? {
        let key = "\(credentialsKeyPrefix)\(provider.rawValue)"
        
        guard let jsonString = userDefaults.string(forKey: key),
              let jsonData = jsonString.data(using: .utf8),
              let credentials = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String] else {
            return nil
        }
        
        return credentials
    }
    
    /// Clear credentials for a provider
    func clearCredentials(for provider: AircraftProviderType) {
        let key = "\(credentialsKeyPrefix)\(provider.rawValue)"
        userDefaults.removeObject(forKey: key)
    }
}

