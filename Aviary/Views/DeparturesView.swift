//
//  DeparturesView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI

/// View displaying departures for an airport
struct DeparturesView: View {
    let airport: Airport
    
    @StateObject private var viewModel = FlightsViewModel()
    
    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.departures.isEmpty {
                ProgressView("Loading departures...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.departures.isEmpty {
                ContentUnavailableView {
                    Label("No Departures", systemImage: "airplane.departure")
                } description: {
                    Text("No departure data available for \(airport.shortCode)")
                } actions: {
                    Button("Refresh") {
                        Task {
                            await viewModel.loadFlights(for: airport.icao, direction: .departure)
                        }
                    }
                }
            } else {
                List {
                    ForEach(viewModel.departures) { flight in
                        FlightRowView(flight: flight)
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await viewModel.loadFlights(for: airport.icao, direction: .departure)
                }
            }
        }
        .task {
            await viewModel.loadFlights(for: airport.icao, direction: .departure)
        }
        .onChange(of: airport.icao) { _, newIcao in
            Task {
                await viewModel.loadFlights(for: newIcao, direction: .departure)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DeparturesView(airport: .sampleLAX)
    }
}

