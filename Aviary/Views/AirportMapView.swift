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
    @State private var showAircraftList = false
    
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
                MapUserLocationButton()
            }
            
            // Overlay controls
            VStack(alignment: .trailing, spacing: 12) {
                // Stats pill
                StatsPillView(
                    airborne: viewModel.airborneCount,
                    onGround: viewModel.groundCount,
                    isLoading: viewModel.isLoading,
                    lastUpdated: viewModel.lastUpdated
                )
                
                // Controls
                VStack(spacing: 8) {
                    // Recenter button
                    Button {
                        withAnimation {
                            mapCameraPosition = .region(MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude),
                                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
                            ))
                        }
                    } label: {
                        Image(systemName: "location.viewfinder")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    
                    // Aircraft list toggle
                    Button {
                        showAircraftList.toggle()
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
            }
            .padding()
            
            // Selected aircraft detail sheet
            if let aircraft = selectedAircraft {
                VStack {
                    Spacer()
                    AircraftDetailCard(aircraft: aircraft) {
                        withAnimation {
                            selectedAircraft = nil
                        }
                    }
                    .padding()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showAircraftList) {
            AircraftListSheet(
                aircraft: viewModel.aircraft,
                onSelect: { aircraft in
                    selectedAircraft = aircraft
                    withAnimation {
                        mapCameraPosition = .region(MKCoordinateRegion(
                            center: aircraft.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                        ))
                    }
                    showAircraftList = false
                }
            )
            .presentationDetents([.medium, .large])
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

// MARK: - Stats Pill View
struct StatsPillView: View {
    let airborne: Int
    let onGround: Int
    let isLoading: Bool
    let lastUpdated: Date?
    
    var body: some View {
        HStack(spacing: 12) {
            // Airborne count
            Label("\(airborne)", systemImage: "airplane")
                .foregroundStyle(.blue)
            
            Divider()
                .frame(height: 16)
            
            // Ground count
            Label("\(onGround)", systemImage: "airplane.circle")
                .foregroundStyle(.gray)
            
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .font(.subheadline)
        .fontWeight(.medium)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Aircraft Detail Card
struct AircraftDetailCard: View {
    let aircraft: LiveAircraft
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(aircraft.displayName)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(aircraft.originCountry)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatItem(
                    title: "Altitude",
                    value: aircraft.altitudeInFeet.map { "\($0) ft" } ?? "—",
                    icon: "arrow.up.forward"
                )
                
                StatItem(
                    title: "Speed",
                    value: aircraft.velocityInKnots.map { "\($0) kts" } ?? "—",
                    icon: "speedometer"
                )
                
                StatItem(
                    title: "Heading",
                    value: aircraft.heading.map { "\(Int($0))°" } ?? "—",
                    icon: "safari"
                )
            }
            
            // Status
            HStack {
                Image(systemName: aircraft.onGround ? "parkingsign.circle.fill" : "airplane.circle.fill")
                    .foregroundStyle(aircraft.onGround ? .orange : .green)
                
                Text(aircraft.onGround ? "On Ground" : "In Flight")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if let rate = aircraft.verticalRate, !aircraft.onGround {
                    HStack(spacing: 4) {
                        Image(systemName: rate > 0 ? "arrow.up.right" : (rate < 0 ? "arrow.down.right" : "arrow.right"))
                            .foregroundStyle(rate > 0 ? .green : (rate < 0 ? .orange : .blue))
                        
                        Text("\(abs(Int(rate * 196.85))) ft/min") // m/s to ft/min
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Stat Item
struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.headline)
            
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Aircraft List Sheet
struct AircraftListSheet: View {
    let aircraft: [LiveAircraft]
    let onSelect: (LiveAircraft) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("In Flight (\(airborneAircraft.count))") {
                    ForEach(airborneAircraft) { ac in
                        AircraftListRow(aircraft: ac)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(ac)
                            }
                    }
                }
                
                Section("On Ground (\(groundAircraft.count))") {
                    ForEach(groundAircraft) { ac in
                        AircraftListRow(aircraft: ac)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(ac)
                            }
                    }
                }
            }
            .navigationTitle("Aircraft")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var airborneAircraft: [LiveAircraft] {
        aircraft.filter { !$0.onGround }.sorted { ($0.altitude ?? 0) > ($1.altitude ?? 0) }
    }
    
    private var groundAircraft: [LiveAircraft] {
        aircraft.filter { $0.onGround }
    }
}

// MARK: - Aircraft List Row
struct AircraftListRow: View {
    let aircraft: LiveAircraft
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: aircraft.onGround ? "airplane.circle" : "airplane")
                .font(.title2)
                .foregroundStyle(aircraft.onGround ? .gray : .blue)
                .rotationEffect(.radians(aircraft.rotationAngle - .pi / 2))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(aircraft.displayName)
                    .font(.headline)
                
                Text(aircraft.originCountry)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if !aircraft.onGround {
                VStack(alignment: .trailing, spacing: 2) {
                    if let alt = aircraft.altitudeInFeet {
                        Text("\(alt) ft")
                            .font(.subheadline)
                    }
                    
                    if let speed = aircraft.velocityInKnots {
                        Text("\(speed) kts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
#Preview {
    AirportMapView(airport: .sampleLAX)
}

