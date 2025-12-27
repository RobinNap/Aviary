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
    
    private var flightService: FlightService
    private var currentIcao: String?
    private var refreshTask: Task<Void, Never>?
    private let settings = FlightServiceSettings.shared
    
    init(flightService: FlightService? = nil) {
        self.flightService = flightService ?? settings.selectedService.createService()
        
        // Listen for service changes
        NotificationCenter.default.addObserver(
            forName: .flightServiceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flightService = self?.settings.selectedService.createService() ?? OpenSkyFlightService.shared
        }
    }
    
    deinit {
        refreshTask?.cancel()
    }
    
    /// Load flights for an airport
    func loadFlights(for icao: String, direction: FlightDirection) async {
        // Don't reload if already loading the same airport
        guard currentIcao != icao || !isLoading else { return }
        
        currentIcao = icao
        isLoading = true
        error = nil
        
        do {
            // Use a more current time range: 1 hour ago to 6 hours from now
            // This ensures we get recent arrivals/departures and upcoming flights
            let now = Date()
            let flights = try await flightService.fetchFlights(
                airportIcao: icao,
                direction: direction,
                from: now.addingTimeInterval(-3600), // 1 hour ago
                to: now.addingTimeInterval(21600)    // 6 hours from now
            )
            
            // Filter flights to ensure they match the airport
            let filteredFlights = flights.filter { flight in
                switch direction {
                case .arrival:
                    // For arrivals, destination must match
                    return flight.destinationIcao?.uppercased() == icao.uppercased()
                case .departure:
                    // For departures, origin must match
                    return flight.originIcao?.uppercased() == icao.uppercased()
                }
            }
            
            switch direction {
            case .arrival:
                arrivals = filteredFlights.sorted { ($0.displayTime ?? .distantPast) < ($1.displayTime ?? .distantPast) }
            case .departure:
                departures = filteredFlights.sorted { ($0.displayTime ?? .distantPast) < ($1.displayTime ?? .distantPast) }
            }
            
            lastUpdated = Date()
        } catch let error as FlightServiceError {
            self.error = error
            print("Error loading flights: \(error)")
            
            // For rate limiting, show a helpful message
            if case .rateLimited = error {
                // Don't clear existing data immediately on rate limit
                // Keep showing what we have, but mark as stale
            } else {
                // For other errors, clear the data
                switch direction {
                case .arrival:
                    arrivals = []
                case .departure:
                    departures = []
                }
            }
        } catch {
            self.error = error
            print("Error loading flights: \(error)")
            
            // Clear data on unknown errors
            switch direction {
            case .arrival:
                arrivals = []
            case .departure:
                departures = []
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
    
    /// Start automatic refresh for an airport
    func startAutoRefresh(for icao: String, interval: TimeInterval = 120) {
        refreshTask?.cancel()
        
        refreshTask = Task {
            while !Task.isCancelled {
                await refreshAll(for: icao)
                
                // Use longer interval if we got rate limited
                let waitInterval: TimeInterval
                if let error = error as? FlightServiceError,
                   case .rateLimited = error {
                    waitInterval = max(interval * 2, 300) // At least 5 minutes if rate limited
                } else {
                    waitInterval = interval
                }
                
                try? await Task.sleep(nanoseconds: UInt64(waitInterval * 1_000_000_000))
            }
        }
    }
    
    /// Stop automatic refresh
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
