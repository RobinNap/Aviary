//
//  AirportMapView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI
import MapKit

/// Live aircraft tracking map view for an airport
struct AirportMapView: View {
    let airport: Airport
    
    @StateObject private var viewModel = LiveAircraftViewModel()
    @State private var selectedAircraft: LiveAircraft?
    @State private var mapCameraPosition: MapCameraPosition
    
    init(airport: Airport) {
        self.airport = airport
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        _mapCameraPosition = State(initialValue: .region(region))
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Map with aircraft
            Map(position: $mapCameraPosition, selection: $selectedAircraft) {
                // Airport marker
                Annotation(airport.shortCode, coordinate: CLLocationCoordinate2D(
                    latitude: airport.latitude,
                    longitude: airport.longitude
                )) {
                    AirportAnnotationView()
                }
                
                // Aircraft markers
                ForEach(viewModel.aircraft) { aircraft in
                    Annotation(aircraft.displayName, coordinate: aircraft.coordinate) {
                        AircraftAnnotationView(
                            aircraft: aircraft,
                            isSelected: selectedAircraft?.id == aircraft.id
                        )
                    }
                    .tag(aircraft)
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including([.airport])))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onChange(of: selectedAircraft) { _, newValue in
                // Prevent selection by immediately clearing it
                if newValue != nil {
                    DispatchQueue.main.async {
                        selectedAircraft = nil
                    }
                }
            }
        }
        .task {
            viewModel.startTracking(
                around: CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude)
            )
        }
        .onDisappear {
            viewModel.stopTracking()
        }
        .onChange(of: airport.icao) { _, _ in
            viewModel.stopTracking()
            viewModel.startTracking(
                around: CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude)
            )
        }
    }
}

// MARK: - Airport Annotation View
struct AirportAnnotationView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.blue.opacity(0.2))
                .frame(width: 60, height: 60)
            
            Circle()
                .fill(.blue.opacity(0.4))
                .frame(width: 40, height: 40)
            
            Image(systemName: "airplane.circle.fill")
                .font(.title)
                .foregroundStyle(.white, .blue)
        }
    }
}

// MARK: - Aircraft Annotation View
struct AircraftAnnotationView: View {
    let aircraft: LiveAircraft
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            // Selection ring
            if isSelected {
                Circle()
                    .stroke(.blue, lineWidth: 2)
                    .frame(width: 40, height: 40)
            }
            
            // Aircraft icon
            Image(systemName: aircraft.onGround ? "airplane.circle" : "airplane")
                .font(.system(size: aircraft.onGround ? 20 : 24))
                .foregroundStyle(aircraftColor)
                .rotationEffect(.radians(aircraft.rotationAngle - .pi / 2)) // Adjust for icon orientation
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        }
        .animation(.easeInOut(duration: 0.3), value: isSelected)
    }
    
    private var aircraftColor: Color {
        if aircraft.onGround {
            return .gray
        } else if let rate = aircraft.verticalRate {
            if rate > 2 {
                return .green // Climbing
            } else if rate < -2 {
                return .orange // Descending
            }
        }
        return .blue // Level flight
    }
}

// MARK: - Preview
#Preview {
    AirportMapView(airport: .sampleLAX)
}

