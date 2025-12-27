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
    
    @State private var selectedTab: AirportTab = .arrivals
    
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
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Airport Tab
enum AirportTab: String, CaseIterable, Identifiable {
    case arrivals
    case departures
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .arrivals: return "Arrivals"
        case .departures: return "Departures"
        }
    }
    
    var icon: String {
        switch self {
        case .arrivals: return "airplane.arrival"
        case .departures: return "airplane.departure"
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
    .modelContainer(for: [ATCFeed.self], inMemory: true)
}
