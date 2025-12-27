//
//  LiveAircraftViewModel.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import CoreLocation
import Combine
import SwiftUI

/// ViewModel for managing live aircraft tracking around an airport
@MainActor
final class LiveAircraftViewModel: ObservableObject {
    @Published private(set) var aircraft: [LiveAircraft] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published private(set) var lastUpdated: Date?
    @Published var isTracking = false
    
    private let service = LiveAircraftService.shared
    private var updateTask: Task<Void, Never>?
    private var currentCenter: CLLocationCoordinate2D?
    
    // Update interval in seconds - as fast as possible while respecting API limits
    private let updateInterval: TimeInterval = 2
    
    /// Start tracking aircraft around the given coordinate
    func startTracking(around center: CLLocationCoordinate2D, radiusDegrees: Double = 0.5) {
        currentCenter = center
        isTracking = true
        
        // Cancel any existing update task
        updateTask?.cancel()
        
        // Start the update loop
        updateTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Initial fetch immediately
            await self.fetchAircraft()
            
            // Continuous updates - fetch as fast as possible
            while !Task.isCancelled && self.isTracking {
                // Wait for minimum interval, but start next fetch immediately after previous completes
                try? await Task.sleep(nanoseconds: UInt64(self.updateInterval * 1_000_000_000))
                
                if Task.isCancelled || !self.isTracking { break }
                
                // Fetch new data (this will respect service-level rate limiting)
                await self.fetchAircraft()
            }
        }
    }
    
    /// Stop tracking aircraft
    func stopTracking() {
        isTracking = false
        updateTask?.cancel()
        updateTask = nil
    }
    
    /// Fetch aircraft once
    func fetchAircraft() async {
        guard let center = currentCenter else { return }
        
        isLoading = true
        error = nil
        
        do {
            let newAircraft = try await service.fetchAircraft(around: center)
            
            // Update aircraft positions instantly with smooth animation
            withAnimation(.easeInOut(duration: 0.2)) {
                self.aircraft = newAircraft
            }
            
            lastUpdated = Date()
        } catch {
            self.error = error
            print("Error fetching aircraft: \(error)")
        }
        
        isLoading = false
    }
    
    /// Update center location and fetch new aircraft
    func updateCenter(_ center: CLLocationCoordinate2D) {
        currentCenter = center
        Task {
            await fetchAircraft()
        }
    }
    
    deinit {
        updateTask?.cancel()
    }
}

// MARK: - Statistics
extension LiveAircraftViewModel {
    /// Number of aircraft currently in the air
    var airborneCount: Int {
        aircraft.filter { !$0.onGround }.count
    }
    
    /// Number of aircraft on the ground
    var groundCount: Int {
        aircraft.filter { $0.onGround }.count
    }
    
    /// Total aircraft count
    var totalCount: Int {
        aircraft.count
    }
}

