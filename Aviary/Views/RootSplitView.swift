//
//  RootSplitView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI
import SwiftData

/// The main navigation structure of the app
struct RootSplitView: View {
    @StateObject private var audioPlayer = AudioPlayer.shared
    @StateObject private var airportCatalog = AirportCatalog.shared
    
    @State private var selectedAirport: Airport?
    @State private var searchText = ""
    
    @AppStorage("app.uiMode") private var uiModeRaw: String = UIMode.pro.rawValue
    
    private var uiMode: UIMode {
        UIMode(rawValue: uiModeRaw) ?? .pro
    }
    
    private var shouldShowCenterPlayer: Bool {
        // Show center player in Simplified mode, or on iPhone (where there's no side panel)
        #if os(iOS)
        return uiMode == .simplified || UIDevice.current.userInterfaceIdiom != .pad
        #else
        return uiMode == .simplified
        #endif
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    if selectedAirport == nil {
                        // Search and results view
                        SearchView(
                            searchText: $searchText,
                            selectedAirport: $selectedAirport,
                            airportCatalog: airportCatalog
                        )
                    } else if let airport = selectedAirport {
                        // Airport detail with back navigation
                        AirportDetailView(airport: airport)
                    }
                }
                
                // ATC Player overlay - shows in Simplified mode or on iPhone
                if let airport = selectedAirport, shouldShowCenterPlayer {
                    VStack {
                        Spacer()
                        AirportATCPlayerView(airport: airport)
                            .padding(.bottom, 8)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(selectedAirport?.shortCode ?? "Aviary")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if selectedAirport != nil {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            // Stop audio if playing a feed from the current airport
                            if let currentFeed = audioPlayer.currentLiveFeed,
                               currentFeed.icao == selectedAirport?.icao {
                                audioPlayer.stop()
                            }
                            withAnimation {
                                selectedAirport = nil
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Search")
                            }
                        }
                    }
                }
                
                ToolbarItem(placement: .automatic) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: selectedAirport)
        .id(uiModeRaw) // Force view refresh when UI mode changes
        .onChange(of: uiModeRaw) { _, _ in
            // Force view update when mode changes
        }
    }
}

// MARK: - Search View
struct SearchView: View {
    @Binding var searchText: String
    @Binding var selectedAirport: Airport?
    @ObservedObject var airportCatalog: AirportCatalog
    
    var body: some View {
        Group {
            if searchText.isEmpty {
                // Full-window empty state
                VStack(spacing: 24) {
                    Spacer()
                    
                    Image(systemName: "airplane.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.tint)
                    
                    VStack(spacing: 8) {
                        Text("Search Airports")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Search for an airport by name, city, or ICAO/IATA code to view arrivals, departures, and listen to ATC.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if airportCatalog.searchResults.isEmpty {
                // Full-window no results state
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Search results list
                List {
                    ForEach(airportCatalog.searchResults) { airport in
                        Button {
                            withAnimation {
                                selectedAirport = airport
                            }
                        } label: {
                            AirportRowView(airport: airport)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search airports...")
        .onChange(of: searchText) { _, newValue in
            airportCatalog.search(query: newValue)
        }
    }
}

// MARK: - Airport Row View
struct AirportRowView: View {
    let airport: Airport
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(airport.shortCode)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if let iata = airport.iata, iata != airport.icao {
                    Text("/ \(airport.icao)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text(airport.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            if let city = airport.city {
                Text(city)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RootSplitView()
        .modelContainer(for: [ATCFeed.self, FlightCacheEntry.self], inMemory: true)
}
