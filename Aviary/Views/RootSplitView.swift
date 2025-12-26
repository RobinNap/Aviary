//
//  RootSplitView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI
import SwiftData

/// The main navigation structure of the app using NavigationSplitView
struct RootSplitView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteAirport.addedAt, order: .reverse) private var favorites: [FavoriteAirport]
    @Query(sort: \RecentAirport.visitedAt, order: .reverse) private var recents: [RecentAirport]
    @StateObject private var audioPlayer = AudioPlayer.shared
    
    @State private var selectedAirport: Airport?
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(
                    selectedAirport: $selectedAirport,
                    searchText: $searchText,
                    isSearching: $isSearching
                )
                .navigationTitle("Aviary")
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
                #endif
            } detail: {
                if let airport = selectedAirport {
                    AirportDetailView(airport: airport)
                } else {
                    WelcomeView()
                }
            }
            .onChange(of: selectedAirport) { _, newAirport in
                if let airport = newAirport {
                    addToRecents(airport)
                }
            }
            
            // Mini Player overlay
            if audioPlayer.currentFeed != nil {
                MiniPlayerView()
                    .padding(.bottom, 8)
            }
        }
    }
    
    private func addToRecents(_ airport: Airport) {
        // Check if already in recents
        if let existing = recents.first(where: { $0.icao == airport.icao }) {
            existing.visitedAt = Date()
        } else {
            let recent = RecentAirport(
                icao: airport.icao,
                iata: airport.iata,
                name: airport.name,
                city: airport.city,
                country: airport.country,
                latitude: airport.latitude,
                longitude: airport.longitude
            )
            modelContext.insert(recent)
            
            // Keep only last 10 recents
            if recents.count > 10 {
                let toDelete = recents.suffix(from: 10)
                for item in toDelete {
                    modelContext.delete(item)
                }
            }
        }
    }
}

// MARK: - Sidebar View
struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteAirport.addedAt, order: .reverse) private var favorites: [FavoriteAirport]
    @Query(sort: \RecentAirport.visitedAt, order: .reverse) private var recents: [RecentAirport]
    
    @Binding var selectedAirport: Airport?
    @Binding var searchText: String
    @Binding var isSearching: Bool
    
    @StateObject private var airportCatalog = AirportCatalog.shared
    
    var body: some View {
        List(selection: $selectedAirport) {
            // Search Section
            if !searchText.isEmpty {
                Section("Search Results") {
                    if airportCatalog.searchResults.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        ForEach(airportCatalog.searchResults) { airport in
                            AirportRowView(airport: airport)
                                .tag(airport)
                        }
                    }
                }
            } else {
                // Favorites Section
                Section("Favorites") {
                    if favorites.isEmpty {
                        Text("No favorites yet")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(favorites) { favorite in
                            AirportRowView(airport: favorite.toAirport())
                                .tag(favorite.toAirport())
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        modelContext.delete(favorite)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                
                // Recents Section
                Section("Recent") {
                    if recents.isEmpty {
                        Text("No recent airports")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(recents.prefix(10)) { recent in
                            AirportRowView(airport: recent.toAirport())
                                .tag(recent.toAirport())
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search airports...")
        .onChange(of: searchText) { _, newValue in
            airportCatalog.search(query: newValue)
        }
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        // Refresh action
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            #endif
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

// MARK: - Welcome View
struct WelcomeView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Welcome to Aviary", systemImage: "airplane.circle.fill")
        } description: {
            Text("Search for an airport or select one from your favorites to view arrivals, departures, and listen to ATC.")
        } actions: {
            Text("Use the search bar to find airports by name, city, or code")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    RootSplitView()
        .modelContainer(for: [FavoriteAirport.self, RecentAirport.self, ATCFeed.self], inMemory: true)
}

