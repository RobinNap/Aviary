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
                emptyStateView
            } else {
                feedListView
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddATCFeedSheet(airport: airport)
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No ATC Feeds", systemImage: "headphones")
        } description: {
            VStack(spacing: 8) {
                Text("Listen to live air traffic control communications")
                Text("Feeds powered by LiveATC.net")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } actions: {
            Button {
                showingAddSheet = true
            } label: {
                Label("Browse LiveATC Feeds", systemImage: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var feedListView: some View {
        List {
            Section {
                ForEach(feeds) { feed in
                    ATCFeedRowView(feed: feed)
                }
                .onDelete(perform: deleteFeeds)
            } header: {
                HStack {
                    Text("Active Feeds")
                    Spacer()
                    Text("\(feeds.count)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            
            Section {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add More Feeds", systemImage: "plus.circle")
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
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
    
    private var isCurrentFeed: Bool {
        audioPlayer.currentFeed?.id == feed.id
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
                
                HStack(spacing: 8) {
                    Label(feed.feedType.displayName, systemImage: feed.feedType.icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if isStreamFromLiveATC {
                        Text("• LiveATC")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                
                if isCurrentFeed {
                    if let error = audioPlayer.error {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error.localizedDescription)
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    } else if isPlaying || isBuffering {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                            Text(audioPlayer.statusMessage ?? (isBuffering ? "Buffering..." : "Live"))
                        }
                        .font(.caption)
                        .foregroundStyle(isBuffering ? .orange : .green)
                    }
                }
            }
            
            Spacer()
            
            // Status Indicator
            if feed.isEnabled {
                Circle()
                    .fill(isCurrentFeed ? .green : .green.opacity(0.5))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    
    private var isStreamFromLiveATC: Bool {
        feed.streamURLString.contains("liveatc.net")
    }
}

#Preview {
    NavigationStack {
        ATCFeedsView(airport: .sampleLAX)
    }
    .modelContainer(for: ATCFeed.self, inMemory: true)
}
