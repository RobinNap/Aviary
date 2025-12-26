//
//  LiveATCFeed.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation

/// Represents a discovered ATC feed from LiveATC.net
/// This is a transient model for feeds that haven't been saved yet
/// Stream URLs are obtained by parsing .pls playlist files from LiveATC
/// Typical format: http://d.liveatc.net/{mount_point}
struct LiveATCFeed: Identifiable, Hashable {
    let id: String
    let icao: String
    let name: String
    let feedType: ATCFeedType
    let streamURL: URL
    let mountPoint: String
    
    /// Convert to a persistable ATCFeed
    func toATCFeed() -> ATCFeed {
        ATCFeed(
            airportIcao: icao,
            name: name,
            streamURL: streamURL,
            feedType: feedType
        )
    }
}

// MARK: - Sample Data
extension LiveATCFeed {
    static let samples: [LiveATCFeed] = [
        LiveATCFeed(
            id: "ksfo_twr",
            icao: "KSFO",
            name: "KSFO Tower",
            feedType: .tower,
            streamURL: URL(string: "http://d.liveatc.net/ksfo_twr")!,
            mountPoint: "ksfo_twr"
        ),
        LiveATCFeed(
            id: "ksfo_gnd",
            icao: "KSFO",
            name: "KSFO Ground",
            feedType: .ground,
            streamURL: URL(string: "http://d.liveatc.net/ksfo_gnd")!,
            mountPoint: "ksfo_gnd"
        ),
        LiveATCFeed(
            id: "ksfo_co",
            icao: "KSFO",
            name: "KSFO Combined",
            feedType: .tower,
            streamURL: URL(string: "http://d.liveatc.net/ksfo_co")!,
            mountPoint: "ksfo_co"
        )
    ]
}
