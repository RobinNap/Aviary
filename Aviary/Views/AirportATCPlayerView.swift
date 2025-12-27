//
//  AirportATCPlayerView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI

/// A player view that shows available ATC feeds for the selected airport
/// Feeds are fetched automatically from LiveATC when an airport is selected
struct AirportATCPlayerView: View {
    let airport: Airport
    
    @StateObject private var audioPlayer = AudioPlayer.shared
    @State private var availableFeeds: [LiveATCFeed] = []
    @State private var isLoadingFeeds = false
    @State private var selectedFeed: LiveATCFeed?
    @State private var showFeedPicker = false
    @State private var loadError: String?
    
    private var isCurrentFeedFromThisAirport: Bool {
        audioPlayer.currentLiveFeed?.icao == airport.icao
    }
    
    private var isLoadingThisAirport: Bool {
        isCurrentFeedFromThisAirport && audioPlayer.isLoading
    }
    
    private var isActivelyPlaying: Bool {
        isCurrentFeedFromThisAirport && audioPlayer.isPlaying
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Feed Selector / Player Area
            if isLoadingFeeds {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Finding feeds...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if availableFeeds.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(.secondary)
                    Text("No ATC feeds available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Feed selector and playback controls
                feedControlsView
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .task(id: airport.icao) {
            await loadFeeds()
        }
    }
    
    // MARK: - Feed Controls
    
    @ViewBuilder
    private var feedControlsView: some View {
        HStack(spacing: 12) {
            // Play/Pause Button
            Button {
                handlePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(isActivelyPlaying ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    if isLoadingThisAirport {
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
            .disabled(isLoadingThisAirport)
            
            // Feed Info & Selector
            VStack(alignment: .leading, spacing: 2) {
                // Current/Selected Feed Name
                Button {
                    showFeedPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Text(currentDisplayFeed?.name ?? "Select Feed")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    #if os(iOS)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    #endif
                }
                .buttonStyle(.plain)
                #if os(iOS)
                .sheet(isPresented: $showFeedPicker) {
                    feedPickerSheetView
                }
                #else
                .popover(isPresented: $showFeedPicker) {
                    feedPickerView
                }
                #endif
                
                // Status Line
                HStack(spacing: 6) {
                    if let feedType = currentDisplayFeed?.feedType {
                        Label(feedType.displayName, systemImage: feedType.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if isActivelyPlaying {
                        Text("• Live")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if isLoadingThisAirport {
                        Text("• \(audioPlayer.statusMessage ?? "Connecting...")")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }
    
    // MARK: - Feed Picker
    
    @ViewBuilder
    private var feedPickerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Available Feeds")
                .font(.headline)
                .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(availableFeeds) { feed in
                        Button {
                            selectAndPlay(feed)
                            showFeedPicker = false
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: feed.feedType.icon)
                                    .frame(width: 24)
                                    .foregroundStyle(Color.accentColor)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feed.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    Text(feed.feedType.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                if audioPlayer.currentLiveFeed?.id == feed.id {
                                    Image(systemName: audioPlayer.isPlaying ? "speaker.wave.2.fill" : "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                audioPlayer.currentLiveFeed?.id == feed.id
                                    ? Color.accentColor.opacity(0.1)
                                    : Color.clear
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 280)
        .background(.ultraThinMaterial)
    }
    
    #if os(iOS)
    @ViewBuilder
    private var feedPickerSheetView: some View {
        NavigationStack {
            Group {
                if availableFeeds.isEmpty {
                    ContentUnavailableView {
                        Label("No Feeds Available", systemImage: "antenna.radiowaves.left.and.right.slash")
                    } description: {
                        Text("No ATC feeds found for \(airport.shortCode)")
                    }
                } else {
                    feedPickerList
                }
            }
            .navigationTitle("Select Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showFeedPicker = false
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var feedPickerList: some View {
        let groupedFeeds = Dictionary(grouping: availableFeeds) { $0.feedType }
        let sortedTypes = ATCFeedType.allCases.filter { groupedFeeds[$0] != nil }
        
        List {
            ForEach(sortedTypes, id: \.self) { feedType in
                if let feeds = groupedFeeds[feedType] {
                    Section {
                        ForEach(feeds) { feed in
                            FeedPickerRowView(
                                feed: feed,
                                isSelected: audioPlayer.currentLiveFeed?.id == feed.id,
                                isPlaying: audioPlayer.currentLiveFeed?.id == feed.id && audioPlayer.isPlaying,
                                onSelect: {
                                    selectAndPlay(feed)
                                    showFeedPicker = false
                                }
                            )
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: feedType.icon)
                                .font(.caption)
                            Text(feedType.displayName)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    #endif
    
    // MARK: - Helpers
    
    private var currentDisplayFeed: LiveATCFeed? {
        if isCurrentFeedFromThisAirport {
            return audioPlayer.currentLiveFeed
        }
        return selectedFeed ?? availableFeeds.first
    }
    
    private func loadFeeds() async {
        isLoadingFeeds = true
        loadError = nil
        
        do {
            availableFeeds = try await LiveATCService.shared.fetchFeeds(for: airport.icao)
            
            // Auto-select first feed if none selected
            if selectedFeed == nil && !availableFeeds.isEmpty {
                selectedFeed = availableFeeds.first
            }
        } catch {
            loadError = error.localizedDescription
        }
        
        isLoadingFeeds = false
    }
    
    private func handlePlayPause() {
        // Don't do anything while loading
        if isLoadingThisAirport {
            return
        }
        
        if isActivelyPlaying {
            audioPlayer.pause()
        } else if audioPlayer.hasFeedLoaded && isCurrentFeedFromThisAirport {
            audioPlayer.resume()
        } else if let feed = selectedFeed ?? availableFeeds.first {
            audioPlayer.play(liveFeed: feed)
        }
    }
    
    private func selectAndPlay(_ feed: LiveATCFeed) {
        selectedFeed = feed
        audioPlayer.play(liveFeed: feed)
    }
}

// MARK: - Feed Picker Row View (iPhone)
#if os(iOS)
struct FeedPickerRowView: View {
    let feed: LiveATCFeed
    let isSelected: Bool
    let isPlaying: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Feed Type Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.accentColor.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: feed.feedType.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.accentColor.opacity(0.8))
                }
                
                // Feed Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(feed.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 6) {
                        if isPlaying {
                            HStack(spacing: 4) {
                                Image(systemName: "waveform")
                                    .font(.caption2)
                                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                                Text("Live")
                            }
                            .font(.caption)
                            .foregroundStyle(.green)
                        } else if isSelected {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Selected")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Selection Indicator
                if isSelected {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.05) : nil)
    }
}
#endif

#Preview {
    VStack {
        Spacer()
        AirportATCPlayerView(airport: .sampleLAX)
    }
    .background(Color.gray.opacity(0.2))
}

