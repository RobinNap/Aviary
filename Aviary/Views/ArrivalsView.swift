//
//  ArrivalsView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI

/// View displaying arrivals for an airport
struct ArrivalsView: View {
    let airport: Airport
    
    @StateObject private var viewModel = FlightsViewModel()
    
    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.arrivals.isEmpty {
                ProgressView("Loading arrivals...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.arrivals.isEmpty {
                ContentUnavailableView {
                    Label("No Arrivals", systemImage: "airplane.arrival")
                } description: {
                    Text("No arrival data available for \(airport.shortCode)")
                } actions: {
                    Button("Refresh") {
                        Task {
                            await viewModel.loadFlights(for: airport.icao, direction: .arrival)
                        }
                    }
                }
            } else {
                List {
                    ForEach(viewModel.arrivals) { flight in
                        FlightRowView(flight: flight)
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await viewModel.loadFlights(for: airport.icao, direction: .arrival)
                }
            }
        }
        .task {
            await viewModel.loadFlights(for: airport.icao, direction: .arrival)
        }
        .onChange(of: airport.icao) { _, newIcao in
            Task {
                await viewModel.loadFlights(for: newIcao, direction: .arrival)
            }
        }
    }
}

// MARK: - Flight Row View
struct FlightRowView: View {
    let flight: Flight
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            Image(systemName: flight.status.iconName)
                .font(.title2)
                .foregroundStyle(statusColor)
                .frame(width: 32)
            
            // Flight Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(flight.displayIdentifier)
                        .font(.headline)
                    
                    if let airline = flight.airline {
                        Text("• \(airline)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                if let otherAirport = flight.otherAirportCode {
                    HStack(spacing: 4) {
                        Text(flight.direction == .arrival ? "From" : "To")
                            .foregroundStyle(.secondary)
                        Text(otherAirport)
                            .fontWeight(.medium)
                        if let name = flight.otherAirportName {
                            Text("(\(name))")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .font(.subheadline)
                }
                
                if let aircraft = flight.aircraft {
                    Text(aircraft)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            // Time and Status
            VStack(alignment: .trailing, spacing: 4) {
                if let time = flight.displayTime {
                    Text(time, style: .time)
                        .font(.headline)
                }
                
                StatusBadge(status: flight.status)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var statusColor: Color {
        switch flight.status {
        case .landed, .departed: return .green
        case .enRoute: return .blue
        case .scheduled: return .secondary
        case .delayed: return .orange
        case .cancelled: return .red
        case .diverted: return .purple
        case .unknown: return .secondary
        }
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let status: FlightStatus
    
    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor.opacity(0.15))
            .foregroundStyle(backgroundColor)
            .clipShape(Capsule())
    }
    
    private var backgroundColor: Color {
        switch status {
        case .landed, .departed: return .green
        case .enRoute: return .blue
        case .scheduled: return .secondary
        case .delayed: return .orange
        case .cancelled: return .red
        case .diverted: return .purple
        case .unknown: return .secondary
        }
    }
}

#Preview {
    NavigationStack {
        ArrivalsView(airport: .sampleLAX)
    }
}

