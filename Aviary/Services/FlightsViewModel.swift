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
/// Uses the same OpenSky Network source as aircraft data
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
    
    init(flightService: FlightService? = nil) {
        // Always use OpenSky Flight Service (same source as aircraft data)
        self.flightService = flightService ?? OpenSkyFlightService.shared
        
        // Listen for aircraft provider changes to sync credentials
        NotificationCenter.default.addObserver(
            forName: .aircraftProviderChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Flight service credentials are automatically synced by AircraftProviderManager
            // Just ensure we're using the shared instance
            // Since we're on the main queue and FlightsViewModel is @MainActor, we can safely mutate
            guard let self = self else { return }
            // Use MainActor.assumeIsolated since we're already on the main actor
            MainActor.assumeIsolated {
                self.flightService = OpenSkyFlightService.shared
            }
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
            // Use different time ranges based on direction
            // Arrivals: Look further back (24 hours) since most have already happened
            // Departures: Look 1 hour back to 6 hours forward for recent and upcoming flights
            let now = Date()
            let from: Date
            let to: Date
            
            switch direction {
            case .arrival:
                // For arrivals, only look backward - arrivals are historical data
                // OpenSky processes arrival data in batches with delays, so we need to look back further
                // Try multiple time ranges as fallbacks since data availability varies
                from = now.addingTimeInterval(-172800) // 48 hours ago
                to = now // Current time (no future window for arrivals)
            case .departure:
                // For departures, look back 1 hour and forward 6 hours
                from = now.addingTimeInterval(-3600)  // 1 hour ago
                to = now.addingTimeInterval(21600)     // 6 hours from now
            }
            
            var flights = try await flightService.fetchFlights(
                airportIcao: icao,
                direction: direction,
                from: from,
                to: to
            )
            
            // For arrivals, try multiple fallback time ranges if the first query returns empty
            // OpenSky processes arrival data in batches, so data availability varies
            if direction == .arrival && flights.isEmpty {
                // Try 1: Last 24 hours
                let ranges: [(TimeInterval, TimeInterval)] = [
                    (-86400, 0),      // Last 24 hours
                    (-259200, -86400), // 24-72 hours ago
                    (-172800, -86400), // 24-48 hours ago
                    (-604800, -172800) // 48 hours to 7 days ago
                ]
                
                for (hoursBack, hoursBackEnd) in ranges {
                    let fallbackFrom = now.addingTimeInterval(hoursBack)
                    let fallbackTo = hoursBackEnd == 0 ? now : now.addingTimeInterval(hoursBackEnd)
                    
                    do {
                        print("FlightsViewModel: Trying arrival fallback range: \(Int(-hoursBack/3600))h to \(Int(-hoursBackEnd/3600))h ago")
                        let fallbackFlights = try await flightService.fetchFlights(
                            airportIcao: icao,
                            direction: direction,
                            from: fallbackFrom,
                            to: fallbackTo
                        )
                        if !fallbackFlights.isEmpty {
                            print("FlightsViewModel: Found \(fallbackFlights.count) arrivals in fallback range")
                            flights = fallbackFlights
                            break
                        }
                    } catch {
                        // Continue to next range
                        print("FlightsViewModel: Fallback range failed: \(error)")
                    }
                }
            }
            
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
                // Arrivals: oldest first (ascending)
                arrivals = filteredFlights.sorted { ($0.displayTime ?? .distantPast) < ($1.displayTime ?? .distantPast) }
            case .departure:
                // Departures: most recent first (descending) - last departed on top
                departures = filteredFlights.sorted { ($0.displayTime ?? .distantPast) > ($1.displayTime ?? .distantPast) }
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
