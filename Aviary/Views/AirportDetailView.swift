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
                    ArrivalsView(airport: airport)
                case .departures:
                    DeparturesView(airport: airport)
                }
            }
            .frame(maxHeight: .infinity)
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

