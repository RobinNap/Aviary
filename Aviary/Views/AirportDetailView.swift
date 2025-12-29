//
//  AirportDetailView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI
import SwiftData

/// Detail view showing airport information and map
struct AirportDetailView: View {
    let airport: Airport
    
    @StateObject private var audioPlayer = AudioPlayer.shared
    
    var body: some View {
        AirportMapView(airport: airport)
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
                    .fixedSize()
                    .padding(.horizontal, 8)
                }
            }
            .onChange(of: airport.icao) { _, newIcao in
                // Stop audio player if playing a feed from a different airport
                if let currentFeed = audioPlayer.currentLiveFeed, currentFeed.icao != newIcao {
                    audioPlayer.stop()
                }
            }
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



#Preview {
    NavigationStack {
        AirportDetailView(airport: .sampleLAX)
    }
    .modelContainer(for: [ATCFeed.self], inMemory: true)
}

