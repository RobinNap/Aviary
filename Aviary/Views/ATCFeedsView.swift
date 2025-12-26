//
//  ATCFeedsView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI
import SwiftData

/// View displaying and managing ATC feeds for an airport
struct ATCFeedsView: View {
    let airport: Airport
    
    @Environment(\.modelContext) private var modelContext
    @Query private var allFeeds: [ATCFeed]
    @State private var showingAddSheet = false
    @StateObject private var audioPlayer = AudioPlayer.shared
    
    private var feeds: [ATCFeed] {
        allFeeds.filter { $0.airportIcao == airport.icao }
    }
    
    var body: some View {
        Group {
            if feeds.isEmpty {
                ContentUnavailableView {
                    Label("No ATC Feeds", systemImage: "headphones")
                } description: {
                    Text("Add ATC stream URLs to listen to tower communications")
                } actions: {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add Feed", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(feeds) { feed in
                        ATCFeedRowView(feed: feed)
                    }
                    .onDelete(perform: deleteFeeds)
                }
                .listStyle(.plain)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddATCFeedSheet(airport: airport)
        }
    }
    
    private func deleteFeeds(at offsets: IndexSet) {
        for index in offsets {
            let feed = feeds[index]
            // Stop playing if this feed is currently playing
            if audioPlayer.currentFeed?.id == feed.id {
                audioPlayer.stop()
            }
            modelContext.delete(feed)
        }
    }
}

// MARK: - ATC Feed Row View
struct ATCFeedRowView: View {
    let feed: ATCFeed
    @StateObject private var audioPlayer = AudioPlayer.shared
    
    private var isPlaying: Bool {
        audioPlayer.currentFeed?.id == feed.id && audioPlayer.isPlaying
    }
    
    private var isBuffering: Bool {
        audioPlayer.currentFeed?.id == feed.id && audioPlayer.isBuffering
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Play Button
            Button {
                if isPlaying {
                    audioPlayer.pause()
                } else {
                    audioPlayer.play(feed: feed)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(isPlaying ? Color.accentColor : Color.secondary.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    if isBuffering {
                        ProgressView()
                            .tint(isPlaying ? .white : .accentColor)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundStyle(isPlaying ? .white : .accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
            
            // Feed Info
            VStack(alignment: .leading, spacing: 4) {
                Text(feed.name)
                    .font(.headline)
                
                Text(feed.feedType.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if isPlaying || isBuffering {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                        Text(isBuffering ? "Buffering..." : "Live")
                    }
                    .font(.caption)
                    .foregroundStyle(.green)
                }
            }
            
            Spacer()
            
            // Status Indicator
            if feed.isEnabled {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        ATCFeedsView(airport: .sampleLAX)
    }
    .modelContainer(for: ATCFeed.self, inMemory: true)
}

