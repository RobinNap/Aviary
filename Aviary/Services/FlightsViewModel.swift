//
//  FlightsViewModel.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import SwiftUI
import Combine

/// ViewModel for managing flight data display
@MainActor
final class FlightsViewModel: ObservableObject {
    @Published private(set) var arrivals: [Flight] = []
    @Published private(set) var departures: [Flight] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published private(set) var lastUpdated: Date?
    
    private let flightService: FlightService
    private var currentIcao: String?
    
    init(flightService: FlightService? = nil) {
        self.flightService = flightService ?? OpenSkyFlightService.shared
    }
    
    /// Load flights for an airport
    func loadFlights(for icao: String, direction: FlightDirection) async {
        // Don't reload if already loading the same airport
        guard currentIcao != icao || !isLoading else { return }
        
        currentIcao = icao
        isLoading = true
        error = nil
        
        do {
            let flights = try await flightService.fetchFlights(
                airportIcao: icao,
                direction: direction,
                from: Date().addingTimeInterval(-7200), // 2 hours ago
                to: Date().addingTimeInterval(14400)    // 4 hours from now
            )
            
            switch direction {
            case .arrival:
                arrivals = flights.sorted { ($0.displayTime ?? .distantPast) < ($1.displayTime ?? .distantPast) }
            case .departure:
                departures = flights.sorted { ($0.displayTime ?? .distantPast) < ($1.displayTime ?? .distantPast) }
            }
            
            lastUpdated = Date()
        } catch {
            self.error = error
            print("Error loading flights: \(error)")
            
            // Use sample data as fallback
            switch direction {
            case .arrival:
                arrivals = Flight.sampleArrivals
            case .departure:
                departures = Flight.sampleDepartures
            }
        }
        
        isLoading = false
    }
    
    /// Refresh all flight data
    func refreshAll(for icao: String) async {
        async let arrivalsTask: () = loadFlights(for: icao, direction: .arrival)
        async let departuresTask: () = loadFlights(for: icao, direction: .departure)
        
        _ = await (arrivalsTask, departuresTask)
    }
}
