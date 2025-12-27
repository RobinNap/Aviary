//
//  AirportDetailView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI
import SwiftData
import MapKit
import Combine
#if os(iOS)
import UIKit
#endif

/// Detail view showing airport information and flights
struct AirportDetailView: View {
    let airport: Airport
    
    @State private var selectedTab: AirportTab = .map
    @StateObject private var audioPlayer = AudioPlayer.shared
    @StateObject private var arrivalsViewModel = FlightsViewModel()
    @StateObject private var departuresViewModel = FlightsViewModel()
    @State private var currentTime = Date()
    @State private var timerPublisher: Timer.TimerPublisher?
    @State private var weather: AirportWeather?
    @State private var isLoadingWeather = false
    
    @AppStorage("app.uiMode") private var uiModeRaw: String = UIMode.pro.rawValue
    
    private var uiMode: UIMode {
        UIMode(rawValue: uiModeRaw) ?? .pro
    }
    
    var body: some View {
        Group {
            // Check UI mode - Simplified mode never shows side panel
            if uiMode == .pro {
                #if os(iOS)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    // iPad: Use side panel layout on the left (non-collapsible)
                    HStack(spacing: 0) {
                        // Side panel (left side) - always visible
                        AirportInfoSidePanel(
                            airport: airport,
                            currentTime: currentTime,
                            weather: weather,
                            isLoadingWeather: isLoadingWeather,
                            audioPlayer: audioPlayer,
                            onCollapse: {} // No-op since it's non-collapsible
                        )
                        .frame(width: 280)
                        .background(Color(uiColor: .systemGroupedBackground))
                        
                        // Main content
                        mainContentView
                    }
                } else {
                    // iPhone: Use regular layout
                    mainContentView
                }
                #elseif os(macOS)
                // Mac: Use side panel layout on the left (non-collapsible)
                HStack(spacing: 0) {
                    // Side panel (left side) - always visible
                    AirportInfoSidePanel(
                        airport: airport,
                        currentTime: currentTime,
                        weather: weather,
                        isLoadingWeather: isLoadingWeather,
                        audioPlayer: audioPlayer,
                        onCollapse: {} // No-op since it's non-collapsible
                    )
                    .frame(width: 280)
                    .background(Color(nsColor: .controlBackgroundColor))
                    
                    // Main content
                    mainContentView
                }
                #else
                mainContentView
                #endif
            } else {
                // Simplified mode: No side panel, just main content
                mainContentView
            }
        }
    }
    
    private var mainContentView: some View {
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
                    ArrivalsView(airport: airport, viewModel: arrivalsViewModel)
                case .departures:
                    DeparturesView(airport: airport, viewModel: departuresViewModel)
                }
            }
            .frame(maxHeight: .infinity)
            .onChange(of: selectedTab) { _, newTab in
                // Only refresh data for the newly selected tab
                switch newTab {
                case .arrivals:
                    Task {
                        await arrivalsViewModel.loadFlights(for: airport.icao, direction: .arrival)
                        arrivalsViewModel.startAutoRefresh(for: airport.icao, interval: 120)
                    }
                    // Stop departures refresh
                    departuresViewModel.stopAutoRefresh()
                case .departures:
                    Task {
                        await departuresViewModel.loadFlights(for: airport.icao, direction: .departure)
                        departuresViewModel.startAutoRefresh(for: airport.icao, interval: 120)
                    }
                    // Stop arrivals refresh
                    arrivalsViewModel.stopAutoRefresh()
                case .map:
                    // Stop both when on map
                    arrivalsViewModel.stopAutoRefresh()
                    departuresViewModel.stopAutoRefresh()
                }
            }
        }
        .navigationTitle(airport.shortCode)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(airport.shortCode)
                        .font(.headline)
                    Text(airport.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .onChange(of: airport.icao) { _, newIcao in
            // Stop audio player if playing a feed from a different airport
            if let currentFeed = audioPlayer.currentLiveFeed, currentFeed.icao != newIcao {
                audioPlayer.stop()
            }
            
            // Stop all refreshes and reload for new airport
            arrivalsViewModel.stopAutoRefresh()
            departuresViewModel.stopAutoRefresh()
            
            // Only load data for the currently active tab
            switch selectedTab {
            case .arrivals:
                Task {
                    await arrivalsViewModel.loadFlights(for: newIcao, direction: .arrival)
                    arrivalsViewModel.startAutoRefresh(for: newIcao, interval: 120)
                }
            case .departures:
                Task {
                    await departuresViewModel.loadFlights(for: newIcao, direction: .departure)
                    departuresViewModel.startAutoRefresh(for: newIcao, interval: 120)
                }
            case .map:
                break
            }
        }
        .onAppear {
            // Load weather data
            Task {
                await loadWeather()
            }
            
            // Load data for the initially selected tab
            switch selectedTab {
            case .arrivals:
                Task {
                    await arrivalsViewModel.loadFlights(for: airport.icao, direction: .arrival)
                    arrivalsViewModel.startAutoRefresh(for: airport.icao, interval: 120)
                }
            case .departures:
                Task {
                    await departuresViewModel.loadFlights(for: airport.icao, direction: .departure)
                    departuresViewModel.startAutoRefresh(for: airport.icao, interval: 120)
                }
            case .map:
                break
            }
        }
        .onChange(of: airport.icao) { _, _ in
            // Reload weather when airport changes
            Task {
                await loadWeather()
            }
        }
        // Update time every second (iPad and Mac only)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                currentTime = Date()
            }
            #elseif os(macOS)
            currentTime = Date()
            #endif
        }
        .id(uiModeRaw) // Force view refresh when UI mode changes
        .onChange(of: uiModeRaw) { _, _ in
            // Force view update when mode changes
        }
    }
    
    // MARK: - Weather Loading
    
    /// Load weather data for the airport
    private func loadWeather() async {
        isLoadingWeather = true
        weather = await WeatherService.shared.fetchWeather(for: airport)
        isLoadingWeather = false
    }
    
}

// MARK: - Audio Player Toolbar View
struct AudioPlayerToolbarView: View {
    @ObservedObject var audioPlayer: AudioPlayer
    
    var body: some View {
        HStack(spacing: 8) {
            Button {
                audioPlayer.togglePlayback()
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            
            if let feedName = audioPlayer.currentFeedName {
                Text(feedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 120)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Weather Toolbar View
struct WeatherToolbarView: View {
    let weather: AirportWeather
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: weatherIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(weather.displayTemperature)
                .font(.caption)
                .fontWeight(.medium)
            
            Text("•")
                .foregroundStyle(.secondary)
                .font(.caption2)
            
            Text(weather.displayWind)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var weatherIcon: String {
        switch weather.condition.lowercased() {
        case "clear", "sunny":
            return "sun.max.fill"
        case "clouds", "cloudy":
            return "cloud.fill"
        case "rain", "drizzle":
            return "cloud.rain.fill"
        case "thunderstorm":
            return "cloud.bolt.fill"
        case "snow":
            return "cloud.snow.fill"
        case "fog", "mist":
            return "cloud.fog.fill"
        default:
            return "cloud.fill"
        }
    }
}

// MARK: - Airport Info Side Panel
struct AirportInfoSidePanel: View {
    let airport: Airport
    let currentTime: Date
    let weather: AirportWeather?
    let isLoadingWeather: Bool
    @ObservedObject var audioPlayer: AudioPlayer
    let onCollapse: () -> Void
    
    private var airportLocalTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium // Includes seconds
        formatter.dateStyle = .none
        
        // Use airport timezone if available, otherwise use system timezone
        if let timezoneString = airport.timezone,
           let timezone = TimeZone(identifier: timezoneString) {
            formatter.timeZone = timezone
        } else {
            // Fallback: estimate timezone from longitude (rough approximation)
            let estimatedOffset = Int(airport.longitude / 15.0)
            if let timezone = TimeZone(secondsFromGMT: estimatedOffset * 3600) {
                formatter.timeZone = timezone
            }
        }
        
        return formatter.string(from: currentTime)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(airport.shortCode)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(airport.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Time Section
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Local Time", systemImage: "clock")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Text(airportLocalTime)
                            .font(.title)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Weather Section
                    if let weather = weather {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Weather", systemImage: "cloud.sun")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 12) {
                                Image(systemName: weatherIcon(for: weather.condition))
                                    .font(.system(size: 40))
                                    .foregroundStyle(.blue)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(weather.displayTemperature)
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                    
                                    Text(weather.description.capitalized)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 6) {
                                WeatherRow(icon: "wind", label: "Wind", value: weather.displayWind)
                                WeatherRow(icon: "humidity", label: "Humidity", value: "\(weather.humidity)%")
                                if let pressure = weather.pressure {
                                    WeatherRow(icon: "gauge", label: "Pressure", value: String(format: "%.0f hPa", pressure))
                                }
                                if let visibility = weather.visibility {
                                    WeatherRow(icon: "eye", label: "Visibility", value: String(format: "%.1f km", visibility / 1000))
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else if isLoadingWeather {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Weather", systemImage: "cloud.sun")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Audio Player Section - Always show for this airport
                    ATCPlayerSidePanelSection(airport: airport)
                }
                .padding()
            }
        }
    }
    
    private func weatherIcon(for condition: String) -> String {
        switch condition.lowercased() {
        case "clear", "sunny":
            return "sun.max.fill"
        case "clouds", "cloudy":
            return "cloud.fill"
        case "rain", "drizzle":
            return "cloud.rain.fill"
        case "thunderstorm":
            return "cloud.bolt.fill"
        case "snow":
            return "cloud.snow.fill"
        case "fog", "mist":
            return "cloud.fog.fill"
        default:
            return "cloud.fill"
        }
    }
}

// MARK: - Weather Row
struct WeatherRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

// MARK: - ATC Player Side Panel Section
struct ATCPlayerSidePanelSection: View {
    let airport: Airport
    
    @StateObject private var audioPlayer = AudioPlayer.shared
    @State private var availableFeeds: [LiveATCFeed] = []
    @State private var isLoadingFeeds = false
    @State private var selectedFeed: LiveATCFeed?
    @State private var showFeedPicker = false
    
    private var isCurrentFeedFromThisAirport: Bool {
        audioPlayer.currentLiveFeed?.icao == airport.icao
    }
    
    private var isActivelyPlaying: Bool {
        isCurrentFeedFromThisAirport && audioPlayer.isPlaying
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ATC Radio", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            if isLoadingFeeds {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Finding feeds...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if availableFeeds.isEmpty {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(.secondary)
                    Text("No feeds available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                // Play/Pause controls
                HStack(spacing: 12) {
                    Button {
                        handlePlayPause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(isActivelyPlaying ? Color.accentColor : Color.secondary.opacity(0.2))
                                .frame(width: 44, height: 44)
                            
                            if audioPlayer.isLoading && isCurrentFeedFromThisAirport {
                                ProgressView()
                                    .tint(isActivelyPlaying ? .white : .accentColor)
                            } else {
                                Image(systemName: isActivelyPlaying ? "pause.fill" : "play.fill")
                                    .font(.title3)
                                    .foregroundStyle(isActivelyPlaying ? .white : .primary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(audioPlayer.isLoading && isCurrentFeedFromThisAirport)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        // Feed selector button
                        Button {
                            showFeedPicker = true
                        } label: {
                            HStack {
                                Text(currentFeedDisplayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Status
                        if audioPlayer.isLoading && isCurrentFeedFromThisAirport {
                            Text("Connecting...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if isActivelyPlaying {
                            Text("Live")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if audioPlayer.hasFeedLoaded && isCurrentFeedFromThisAirport {
                            Text("Paused")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showFeedPicker) {
            FeedPickerSheet(availableFeeds: availableFeeds, selectedFeed: $selectedFeed, audioPlayer: audioPlayer, airport: airport)
        }
        .task(id: airport.icao) {
            await loadFeeds()
        }
    }
    
    private var currentFeedDisplayName: String {
        if isCurrentFeedFromThisAirport, let feedName = audioPlayer.currentFeedName {
            return feedName
        }
        return selectedFeed?.name ?? availableFeeds.first?.name ?? "Select Feed"
    }
    
    private func loadFeeds() async {
        isLoadingFeeds = true
        do {
            availableFeeds = try await LiveATCService.shared.fetchFeeds(for: airport.icao)
            if selectedFeed == nil && !availableFeeds.isEmpty {
                selectedFeed = availableFeeds.first
            }
        } catch {
            print("Failed to load feeds: \(error)")
        }
        isLoadingFeeds = false
    }
    
    private func handlePlayPause() {
        if isActivelyPlaying {
            audioPlayer.pause()
        } else if audioPlayer.hasFeedLoaded && isCurrentFeedFromThisAirport {
            audioPlayer.resume()
        } else if let feed = selectedFeed ?? availableFeeds.first {
            audioPlayer.play(liveFeed: feed)
        }
    }
}

// MARK: - Feed Picker Sheet
struct FeedPickerSheet: View {
    let availableFeeds: [LiveATCFeed]
    @Binding var selectedFeed: LiveATCFeed?
    @ObservedObject var audioPlayer: AudioPlayer
    let airport: Airport
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(availableFeeds) { feed in
                    Button {
                        selectedFeed = feed
                        audioPlayer.play(liveFeed: feed)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feed.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(feed.feedType.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if audioPlayer.currentLiveFeed?.id == feed.id && audioPlayer.isPlaying {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select ATC Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
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

