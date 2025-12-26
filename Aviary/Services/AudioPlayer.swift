//
//  AudioPlayer.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import AVFoundation
import Combine

/// Audio player service for streaming ATC feeds
@MainActor
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()
    
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var currentFeed: ATCFeed?
    @Published private(set) var error: Error?
    @Published private(set) var volume: Float = 1.0
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var statusObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    
    private init() {
        setupAudioSession()
    }
    
    // MARK: - Public Methods
    
    /// Play an ATC feed
    func play(feed: ATCFeed) {
        guard let url = feed.streamURL else {
            error = AudioPlayerError.invalidURL
            return
        }
        
        // Stop current playback
        stop()
        
        currentFeed = feed
        isBuffering = true
        error = nil
        
        // Create player item and player
        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        
        // Observe player item status
        statusObserver = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.handleStatusChange(item.status)
            }
        }
        
        // Observe buffering state
        bufferObserver = playerItem?.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.isBuffering = !(item.isPlaybackLikelyToKeepUp)
            }
        }
        
        // Start playback
        player?.play()
        isPlaying = true
        
        // Update last played timestamp
        feed.lastPlayedAt = Date()
    }
    
    /// Pause playback
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    /// Resume playback
    func resume() {
        guard player != nil else { return }
        player?.play()
        isPlaying = true
    }
    
    /// Toggle play/pause
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }
    
    /// Stop playback and cleanup
    func stop() {
        player?.pause()
        
        statusObserver?.invalidate()
        statusObserver = nil
        
        bufferObserver?.invalidate()
        bufferObserver = nil
        
        playerItem = nil
        player = nil
        
        isPlaying = false
        isBuffering = false
        currentFeed = nil
        error = nil
    }
    
    /// Set playback volume
    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        player?.volume = volume
    }
    
    // MARK: - Private Methods
    
    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
        #endif
    }
    
    private func handleStatusChange(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            isBuffering = false
        case .failed:
            isPlaying = false
            isBuffering = false
            error = playerItem?.error ?? AudioPlayerError.playbackFailed
        case .unknown:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - Audio Player Errors
enum AudioPlayerError: LocalizedError {
    case invalidURL
    case playbackFailed
    case notAvailable
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid stream URL"
        case .playbackFailed:
            return "Playback failed"
        case .notAvailable:
            return "Audio playback not available"
        }
    }
}
