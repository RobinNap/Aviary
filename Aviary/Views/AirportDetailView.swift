//
//  AirportDetailView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI
import SwiftData
import MapKit

/// Detail view showing airport information and flights
struct AirportDetailView: View {
    let airport: Airport
    
    @State private var selectedTab: AirportTab = .map
    @StateObject private var audioPlayer = AudioPlayer.shared
    @StateObject private var arrivalsViewModel = FlightsViewModel()
    @StateObject private var departuresViewModel = FlightsViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Selector
            Picker("View", selection: $selectedTab) {
                ForEach(AirportTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 12)
            
            // Tab Content
            Group {
                switch selectedTab {
                case .map:
                    AirportMapView(airport: airport)
                case .arrivals:
                    ArrivalsView(airport: airport, viewModel: arrivalsViewModel)
                case .departures:
                    DeparturesView(airport: airport, viewModel: departuresViewModel)
                }
            }
            .frame(maxHeight: .infinity)
            .onChange(of: selectedTab) { _, newTab in
                // Only refresh data for the newly selected tab
                switch newTab {
                case .arrivals:
                    Task {
                        await arrivalsViewModel.loadFlights(for: airport.icao, direction: .arrival)
                        arrivalsViewModel.startAutoRefresh(for: airport.icao, interval: 120)
                    }
                    // Stop departures refresh
                    departuresViewModel.stopAutoRefresh()
                case .departures:
                    Task {
                        await departuresViewModel.loadFlights(for: airport.icao, direction: .departure)
                        departuresViewModel.startAutoRefresh(for: airport.icao, interval: 120)
                    }
                    // Stop arrivals refresh
                    arrivalsViewModel.stopAutoRefresh()
                case .map:
                    // Stop both when on map
                    arrivalsViewModel.stopAutoRefresh()
                    departuresViewModel.stopAutoRefresh()
                }
            }
        }
        .navigationTitle(airport.shortCode)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(airport.shortCode)
                        .font(.headline)
                    Text(airport.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .onChange(of: airport.icao) { _, newIcao in
            // Stop audio player if playing a feed from a different airport
            if let currentFeed = audioPlayer.currentLiveFeed, currentFeed.icao != newIcao {
                audioPlayer.stop()
            }
            
            // Stop all refreshes and reload for new airport
            arrivalsViewModel.stopAutoRefresh()
            departuresViewModel.stopAutoRefresh()
            
            // Only load data for the currently active tab
            switch selectedTab {
            case .arrivals:
                Task {
                    await arrivalsViewModel.loadFlights(for: newIcao, direction: .arrival)
                    arrivalsViewModel.startAutoRefresh(for: newIcao, interval: 120)
                }
            case .departures:
                Task {
                    await departuresViewModel.loadFlights(for: newIcao, direction: .departure)
                    departuresViewModel.startAutoRefresh(for: newIcao, interval: 120)
                }
            case .map:
                break
            }
        }
        .onAppear {
            // Load data for the initially selected tab
            switch selectedTab {
            case .arrivals:
                Task {
                    await arrivalsViewModel.loadFlights(for: airport.icao, direction: .arrival)
                    arrivalsViewModel.startAutoRefresh(for: airport.icao, interval: 120)
                }
            case .departures:
                Task {
                    await departuresViewModel.loadFlights(for: airport.icao, direction: .departure)
                    departuresViewModel.startAutoRefresh(for: airport.icao, interval: 120)
                }
            case .map:
                break
            }
        }
    }
}

// MARK: - Airport Tab
enum AirportTab: String, CaseIterable, Identifiable {
    case map
    case arrivals
    case departures
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .map: return "Map"
        case .arrivals: return "Arrivals"
        case .departures: return "Departures"
        }
    }
    
    var icon: String {
        switch self {
        case .map: return "map"
        case .arrivals: return "airplane.arrival"
        case .departures: return "airplane.departure"
        }
    }
}

#Preview {
    NavigationStack {
        AirportDetailView(airport: .sampleLAX)
    }
    .modelContainer(for: [ATCFeed.self], inMemory: true)
}

