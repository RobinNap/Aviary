//
//  AirportDetailView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI
import SwiftData
import MapKit

/// Detail view showing airport information, flights, and ATC feeds
struct AirportDetailView: View {
    let airport: Airport
    
    @Environment(\.modelContext) private var modelContext
    @Query private var favorites: [FavoriteAirport]
    
    @State private var selectedTab: AirportTab = .arrivals
    
    private var isFavorite: Bool {
        favorites.contains { $0.icao == airport.icao }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Airport Header
            AirportHeaderView(airport: airport)
            
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
                case .arrivals:
                    ArrivalsView(airport: airport)
                case .departures:
                    DeparturesView(airport: airport)
                case .atc:
                    ATCFeedsView(airport: airport)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .navigationTitle(airport.shortCode)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .secondary)
                }
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
            
            ToolbarItem(placement: .secondaryAction) {
                ShareLink(item: airport.name) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
    
    private func toggleFavorite() {
        if let existing = favorites.first(where: { $0.icao == airport.icao }) {
            modelContext.delete(existing)
        } else {
            let favorite = FavoriteAirport(
                icao: airport.icao,
                iata: airport.iata,
                name: airport.name,
                city: airport.city,
                country: airport.country,
                latitude: airport.latitude,
                longitude: airport.longitude
            )
            modelContext.insert(favorite)
        }
    }
}

// MARK: - Airport Tab
enum AirportTab: String, CaseIterable, Identifiable {
    case arrivals
    case departures
    case atc
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .arrivals: return "Arrivals"
        case .departures: return "Departures"
        case .atc: return "ATC"
        }
    }
    
    var icon: String {
        switch self {
        case .arrivals: return "airplane.arrival"
        case .departures: return "airplane.departure"
        case .atc: return "headphones"
        }
    }
}

// MARK: - Airport Header View
struct AirportHeaderView: View {
    let airport: Airport
    
    var body: some View {
        VStack(spacing: 12) {
            // Map Preview
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            ))) {
                Marker(airport.shortCode, coordinate: CLLocationCoordinate2D(
                    latitude: airport.latitude,
                    longitude: airport.longitude
                ))
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .allowsHitTesting(false)
            
            // Airport Info
            VStack(spacing: 4) {
                Text(airport.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 8) {
                    Text(airport.fullCode)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.15))
                        .clipShape(Capsule())
                    
                    if let city = airport.city, let country = airport.country {
                        Text("\(city), \(country)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let elevation = airport.elevation {
                    Text("Elevation: \(elevation) ft")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    NavigationStack {
        AirportDetailView(airport: .sampleLAX)
    }
    .modelContainer(for: [FavoriteAirport.self, RecentAirport.self, ATCFeed.self], inMemory: true)
}

