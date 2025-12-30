//
//  AirportMapView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI
import MapKit
#if os(macOS)
import AppKit
#endif

/// Live aircraft tracking map view for an airport
struct AirportMapView: View {
    let airport: Airport
    
    @StateObject private var viewModel = LiveAircraftViewModel()
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
            Map(position: $mapCameraPosition) {
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
                        AircraftAnnotationView(aircraft: aircraft)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including([.airport])))
            .mapControls {
                MapCompass()
                MapScaleView()
                #if os(macOS)
                MapZoomStepper()
                #endif
            }
            #if os(macOS)
            .overlay(CursorModifier())
            #endif
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
    
    var body: some View {
        // Aircraft icon
        Image(systemName: aircraft.onGround ? "airplane.circle" : "airplane")
            .font(.system(size: aircraft.onGround ? 20 : 24))
            .foregroundStyle(aircraftColor)
            .rotationEffect(.radians(aircraft.rotationAngle - .pi / 2)) // Adjust for icon orientation
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
    }
    
    private var aircraftColor: Color {
        if aircraft.onGround {
            return .gray
        } else {
            return .blue // In the air
        }
    }
}

// MARK: - Cursor Modifier
#if os(macOS)
struct CursorModifier: View {
    var body: some View {
        CursorTrackingView()
            .allowsHitTesting(false)
    }
}

struct CursorTrackingView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = CursorTrackingNSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Update if needed
    }
}

class CursorTrackingNSView: NSView {
    override func awakeFromNib() {
        super.awakeFromNib()
        setupTracking()
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupTracking()
    }
    
    func setupTracking() {
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
    }
    
    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        setupTracking()
    }
}
#endif

// MARK: - Preview
#Preview {
    AirportMapView(airport: .sampleLAX)
}

