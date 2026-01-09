//
//  RootSplitView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// The main navigation structure of the app
struct RootSplitView: View {
    @StateObject private var audioPlayer = AudioPlayer.shared
    @StateObject private var airportCatalog = AirportCatalog.shared
    
    @State private var selectedAirport: Airport?
    @State private var searchText = ""
    
    private var shouldShowCenterPlayer: Bool {
        // Always show center player
        return true
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
            .navigationTitle(selectedAirport == nil ? "Aviary" : "")
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
    }
}

// MARK: - Search View
struct SearchView: View {
    @Binding var searchText: String
    @Binding var selectedAirport: Airport?
    @ObservedObject var airportCatalog: AirportCatalog
    
    #if os(macOS)
    @State private var selectedIndex: Int? = nil
    #endif
    
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
                        
                        Text("Search for an airport by name, city, or ICAO/IATA code to view the map and listen to ATC.")
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
                // Search results list - optimized for Mac
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(airportCatalog.searchResults.enumerated()), id: \.element.id) { index, airport in
                                AirportRowView(
                                    airport: airport,
                                    isSelected: {
                                        #if os(macOS)
                                        return selectedIndex == index
                                        #else
                                        return false
                                        #endif
                                    }()
                                )
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation {
                                        selectedAirport = airport
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #if os(macOS)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .focusable()
                    .onAppear {
                        // Reset selection when results change
                        selectedIndex = airportCatalog.searchResults.isEmpty ? nil : 0
                        if !airportCatalog.searchResults.isEmpty {
                            proxy.scrollTo(0, anchor: .top)
                        }
                    }
                    .onChange(of: airportCatalog.searchResults) { _, _ in
                        selectedIndex = airportCatalog.searchResults.isEmpty ? nil : 0
                        if !airportCatalog.searchResults.isEmpty {
                            proxy.scrollTo(0, anchor: .top)
                        }
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        if let index = newIndex, index < airportCatalog.searchResults.count {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(index, anchor: .center)
                            }
                        }
                    }
                    .onKeyPress(.upArrow) {
                        if let current = selectedIndex, current > 0 {
                            selectedIndex = current - 1
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.downArrow) {
                        if let current = selectedIndex {
                            if current < airportCatalog.searchResults.count - 1 {
                                selectedIndex = current + 1
                                return .handled
                            }
                        } else if !airportCatalog.searchResults.isEmpty {
                            selectedIndex = 0
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.return) {
                        if let index = selectedIndex, index < airportCatalog.searchResults.count {
                            withAnimation {
                                selectedAirport = airportCatalog.searchResults[index]
                            }
                            return .handled
                        }
                        return .ignored
                    }
                    #endif
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search airports...")
        .onChange(of: searchText) { _, newValue in
            // Clear selectedAirport when user starts typing to show search results instead of detail view
            if !newValue.isEmpty && selectedAirport != nil {
                withAnimation {
                    selectedAirport = nil
                }
            }
            
            airportCatalog.search(query: newValue)
        }
    }
}

// MARK: - Airport Row View
struct AirportRowView: View {
    let airport: Airport
    var isSelected: Bool = false
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Airport code badge
            VStack(spacing: 2) {
                Text(airport.shortCode)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                
                if let iata = airport.iata, iata != airport.icao {
                    Text(airport.icao)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 60, alignment: .leading)
            
            // Airport details
            VStack(alignment: .leading, spacing: 4) {
                Text(airport.name)
                    .font(.system(.body))
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 6) {
                    if let city = airport.city {
                        Label(city, systemImage: "mappin.circle.fill")
                            .font(.system(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    
                    if let country = airport.country {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(country)
                            .font(.system(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Chevron indicator
            Image(systemName: "chevron.right")
                .font(.system(.caption))
                .foregroundStyle(.tertiary)
                .opacity(isHovered ? 1 : 0.3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        #if os(macOS)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected || isHovered ? Color.accentColor.opacity(isSelected ? 0.15 : 0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        #else
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        #endif
        .padding(.horizontal, 16)
    }
}

#Preview {
    RootSplitView()
        .modelContainer(for: [ATCFeed.self, FlightCacheEntry.self], inMemory: true)
}

