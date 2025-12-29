//
//  ATCFeed.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import SwiftData

/// Type of ATC feed
enum ATCFeedType: String, Codable, CaseIterable {
    case tower
    case ground
    case approach
    case departure
    case center
    case clearance
    case atis
    case other
    
    var displayName: String {
        switch self {
        case .tower: return "Tower"
        case .ground: return "Ground"
        case .approach: return "Approach"
        case .departure: return "Departure"
        case .center: return "Center"
        case .clearance: return "Clearance"
        case .atis: return "ATIS"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .tower: return "building.2"
        case .ground: return "figure.walk"
        case .approach: return "airplane.arrival"
        case .departure: return "airplane.departure"
        case .center: return "scope"
        case .clearance: return "checkmark.seal"
        case .atis: return "info.circle"
        case .other: return "antenna.radiowaves.left.and.right"
        }
    }
}

/// Persisted ATC feed for an airport
@Model
final class ATCFeed {
    var id: UUID
    var airportIcao: String
    var name: String
    var streamURLString: String
    var feedTypeRaw: String
    var isEnabled: Bool
    var addedAt: Date
    var lastPlayedAt: Date?
    
    var streamURL: URL? {
        URL(string: streamURLString)
    }
    
    var feedType: ATCFeedType {
        get { ATCFeedType(rawValue: feedTypeRaw) ?? .other }
        set { feedTypeRaw = newValue.rawValue }
    }
    
    init(
        airportIcao: String,
        name: String,
        streamURL: URL,
        feedType: ATCFeedType = .tower,
        isEnabled: Bool = true
    ) {
        self.id = UUID()
        self.airportIcao = airportIcao
        self.name = name
        self.streamURLString = streamURL.absoluteString
        self.feedTypeRaw = feedType.rawValue
        self.isEnabled = isEnabled
        self.addedAt = Date()
        self.lastPlayedAt = nil
    }
}

// MARK: - Sample Data
extension ATCFeed {
    static func sample(for airport: Airport) -> ATCFeed {
        ATCFeed(
            airportIcao: airport.icao,
            name: "\(airport.shortCode) Tower",
            streamURL: URL(string: "https://example.com/stream")!,
            feedType: .tower
        )
    }
}



