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
    
    @ObservedObject var viewModel: FlightsViewModel
    
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
                VStack(spacing: 0) {
                    // Rate limit warning
                    if let error = viewModel.error as? FlightServiceError,
                       case .rateLimited = error {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Rate limited. Please wait before refreshing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                    }
                    
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
        }
        .onDisappear {
            // Stop auto-refresh when view disappears
            viewModel.stopAutoRefresh()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
    }
}

#Preview {
    NavigationStack {
        DeparturesView(airport: .sampleLAX, viewModel: FlightsViewModel())
    }
}

