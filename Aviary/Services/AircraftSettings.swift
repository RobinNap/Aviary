//
//  AircraftSettings.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation

/// Manages aircraft data provider settings
final class AircraftSettings {
    static let shared = AircraftSettings()
    
    private let userDefaults = UserDefaults.standard
    private let selectedProviderKey = "aircraft.selectedProvider"
    private let credentialsKeyPrefix = "aircraft.credentials."
    
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

