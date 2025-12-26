//
//  MiniPlayerView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI
import SwiftData

/// A compact player view that shows when ATC audio is playing
struct MiniPlayerView: View {
    @StateObject private var audioPlayer = AudioPlayer.shared
    
    var body: some View {
        if let feed = audioPlayer.currentFeed {
            HStack(spacing: 12) {
                // Waveform animation
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green)
                            .frame(width: 3, height: audioPlayer.isPlaying ? CGFloat.random(in: 8...20) : 8)
                            .animation(
                                audioPlayer.isPlaying ?
                                    .easeInOut(duration: 0.3)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.1) :
                                    .default,
                                value: audioPlayer.isPlaying
                            )
                    }
                }
                .frame(width: 24, height: 24)
                
                // Feed Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(feed.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(feed.feedType.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if audioPlayer.isBuffering {
                            Text("• Buffering...")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if audioPlayer.isPlaying {
                            Text("• Live")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                
                Spacer()
                
                // Play/Pause Button
                Button {
                    audioPlayer.togglePlayback()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(audioPlayer.isPlaying ? "Pause" : "Play")
                
                // Stop Button
                Button {
                    audioPlayer.stop()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            .padding(.horizontal)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

#Preview {
    VStack {
        Spacer()
        MiniPlayerView()
    }
    .modelContainer(for: ATCFeed.self, inMemory: true)
}

