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
    @Published private(set) var isConnecting = false
    @Published private(set) var currentFeed: ATCFeed?
    @Published private(set) var currentLiveFeed: LiveATCFeed?
    @Published private(set) var error: Error?
    @Published private(set) var volume: Float = 1.0
    @Published private(set) var statusMessage: String?
    
    /// Whether the player is loading (connecting or buffering)
    var isLoading: Bool {
        isConnecting || isBuffering
    }
    
    /// The name of the currently playing feed (works for both ATCFeed and LiveATCFeed)
    var currentFeedName: String? {
        currentFeed?.name ?? currentLiveFeed?.name
    }
    
    /// The feed type of the currently playing feed
    var currentFeedType: ATCFeedType? {
        currentFeed?.feedType ?? currentLiveFeed?.feedType
    }
    
    /// Whether any feed is currently loaded (playing or paused)
    var hasFeedLoaded: Bool {
        currentFeed != nil || currentLiveFeed != nil
    }
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var statusObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    private var errorObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    
    private init() {
        setupAudioSession()
    }
    
    // MARK: - Public Methods
    
    /// Play an ATC feed
    func play(feed: ATCFeed) {
        guard let url = feed.streamURL else {
            error = AudioPlayerError.invalidURL
            statusMessage = "Invalid stream URL"
            return
        }
        
        print("AudioPlayer: Attempting to play URL: \(url.absoluteString)")
        
        // Stop current playback
        stop()
        
        currentFeed = feed
        currentLiveFeed = nil
        isConnecting = true
        isBuffering = false
        error = nil
        statusMessage = "Connecting..."
        
        // Create the player item
        // For HTTP Icecast streams, we need to handle them carefully
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "AVPlayer/1.0 Aviary",
                "Accept": "*/*",
                "Icy-MetaData": "1"  // Request Icecast metadata
            ]
        ])
        
        playerItem = AVPlayerItem(asset: asset)
        
        // Set buffer preferences for live streaming
        playerItem?.preferredForwardBufferDuration = 1
        playerItem?.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        player?.automaticallyWaitsToMinimizeStalling = false
        
        // Observe player item status
        statusObserver = playerItem?.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.handleStatusChange(item.status)
            }
        }
        
        // Observe buffering state
        bufferObserver = playerItem?.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                if item.isPlaybackLikelyToKeepUp {
                    self?.isBuffering = false
                    self?.statusMessage = "Live"
                }
            }
        }
        
        // Observe player item error
        errorObserver = playerItem?.observe(\.error, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                if let error = item.error {
                    self?.handleError(error)
                }
            }
        }
        
        // Observe player time control status (playing/paused/waiting)
        timeControlObserver = player?.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.handleTimeControlChange(player.timeControlStatus)
            }
        }
        
        // Observe for errors via notification
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                Task { @MainActor [weak self] in
                    self?.handleError(error)
                }
            }
        }
        
        // Start playback - isPlaying will be set to true when timeControlStatus changes to .playing
        player?.play()
        
        // Update last played timestamp
        feed.lastPlayedAt = Date()
    }
    
    /// Play a LiveATC feed directly without saving
    func play(liveFeed: LiveATCFeed) {
        let url = liveFeed.streamURL
        
        print("AudioPlayer: Attempting to play LiveATC feed: \(url.absoluteString)")
        
        // Stop current playback
        stop()
        
        currentLiveFeed = liveFeed
        currentFeed = nil
        isConnecting = true
        isBuffering = false
        error = nil
        statusMessage = "Connecting..."
        
        // Create the player item
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "AVPlayer/1.0 Aviary",
                "Accept": "*/*",
                "Icy-MetaData": "1"
            ]
        ])
        
        playerItem = AVPlayerItem(asset: asset)
        playerItem?.preferredForwardBufferDuration = 1
        playerItem?.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        player?.automaticallyWaitsToMinimizeStalling = false
        
        // Observe player item status
        statusObserver = playerItem?.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.handleStatusChange(item.status)
            }
        }
        
        // Observe buffering state
        bufferObserver = playerItem?.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                if item.isPlaybackLikelyToKeepUp {
                    self?.isBuffering = false
                    self?.statusMessage = "Live"
                }
            }
        }
        
        // Observe player item error
        errorObserver = playerItem?.observe(\.error, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                if let error = item.error {
                    self?.handleError(error)
                }
            }
        }
        
        // Observe player time control status
        timeControlObserver = player?.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.handleTimeControlChange(player.timeControlStatus)
            }
        }
        
        // Observe for errors via notification
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                Task { @MainActor [weak self] in
                    self?.handleError(error)
                }
            }
        }
        
        // Start playback - isPlaying will be set to true when timeControlStatus changes to .playing
        player?.play()
    }
    
    /// Play directly from a URL (for testing)
    func playURL(_ url: URL) {
        print("AudioPlayer: Playing direct URL: \(url.absoluteString)")
        
        stop()
        
        isConnecting = true
        isBuffering = false
        error = nil
        statusMessage = "Connecting..."
        
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "AVPlayer/1.0 Aviary",
                "Accept": "*/*"
            ]
        ])
        
        playerItem = AVPlayerItem(asset: asset)
        playerItem?.preferredForwardBufferDuration = 1
        
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        player?.automaticallyWaitsToMinimizeStalling = false
        
        statusObserver = playerItem?.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.handleStatusChange(item.status)
            }
        }
        
        bufferObserver = playerItem?.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                if item.isPlaybackLikelyToKeepUp {
                    self?.isBuffering = false
                    self?.statusMessage = "Playing"
                }
            }
        }
        
        player?.play()
    }
    
    /// Pause playback
    func pause() {
        player?.pause()
        isPlaying = false
        statusMessage = "Paused"
    }
    
    /// Resume playback
    func resume() {
        guard player != nil else { return }
        player?.play()
        isPlaying = true
        statusMessage = "Live"
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
        
        NotificationCenter.default.removeObserver(self)
        
        statusObserver?.invalidate()
        statusObserver = nil
        
        bufferObserver?.invalidate()
        bufferObserver = nil
        
        errorObserver?.invalidate()
        errorObserver = nil
        
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        
        playerItem = nil
        player = nil
        
        isPlaying = false
        isBuffering = false
        isConnecting = false
        currentFeed = nil
        currentLiveFeed = nil
        error = nil
        statusMessage = nil
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
            print("AudioPlayer: Failed to setup audio session: \(error)")
        }
        #endif
    }
    
    private func handleStatusChange(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            print("AudioPlayer: Ready to play - stream connected successfully")
            isConnecting = false
            // Ensure playback starts when stream is ready
            if hasFeedLoaded {
                player?.play()
                // Check if player is already playing (timeControlStatus might have fired first)
                if player?.timeControlStatus == .playing {
                    isBuffering = false
                    isPlaying = true
                    statusMessage = "Live"
                }
            }
        case .failed:
            isPlaying = false
            isBuffering = false
            isConnecting = false
            let playerError = playerItem?.error
            error = playerError ?? AudioPlayerError.playbackFailed
            
            // Extract detailed error info
            let errorDescription = describeError(playerError)
            statusMessage = "Failed: \(errorDescription)"
            print("AudioPlayer: FAILED - \(errorDescription)")
            
            if let nsError = playerError as NSError? {
                print("AudioPlayer: Error domain: \(nsError.domain)")
                print("AudioPlayer: Error code: \(nsError.code)")
                print("AudioPlayer: Error userInfo: \(nsError.userInfo)")
            }
        case .unknown:
            statusMessage = "Connecting..."
            print("AudioPlayer: Status unknown, waiting...")
        @unknown default:
            break
        }
    }
    
    private func handleTimeControlChange(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .paused:
            // Check if we intended to be playing - if so, this is unexpected
            if hasFeedLoaded && isPlaying {
                print("AudioPlayer: Playback paused unexpectedly, attempting to resume...")
                // Check if the player item is ready and we should resume
                if playerItem?.status == .readyToPlay {
                    // Small delay to avoid rapid play/pause cycles
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                        if self.hasFeedLoaded && self.playerItem?.status == .readyToPlay {
                            self.player?.play()
                            print("AudioPlayer: Resumed playback")
                        }
                    }
                }
            } else if !hasFeedLoaded {
                isPlaying = false
            }
        case .waitingToPlayAtSpecifiedRate:
            // If we're past the initial connection, this is buffering
            if !isConnecting {
                isBuffering = true
                statusMessage = "Buffering..."
            } else {
                statusMessage = "Connecting..."
            }
            print("AudioPlayer: Waiting/Buffering")
            
            // Log the reason for waiting
            if let reason = player?.reasonForWaitingToPlay {
                print("AudioPlayer: Waiting reason: \(reason.rawValue)")
            }
        case .playing:
            // Only transition to playing state if we've received readyToPlay status
            // This prevents premature "Live" state during initial connection
            if !isConnecting {
                isBuffering = false
                isPlaying = true
                statusMessage = "Live"
                print("AudioPlayer: Now playing audio")
            } else {
                print("AudioPlayer: TimeControl says playing but still connecting, waiting for readyToPlay...")
            }
        @unknown default:
            break
        }
    }
    
    private func handleError(_ error: Error) {
        self.error = error
        self.isPlaying = false
        self.isBuffering = false
        
        let errorDescription = describeError(error)
        self.statusMessage = "Error: \(errorDescription)"
        print("AudioPlayer: ERROR - \(errorDescription)")
        
        if let nsError = error as NSError? {
            print("AudioPlayer: Error domain: \(nsError.domain)")
            print("AudioPlayer: Error code: \(nsError.code)")
            print("AudioPlayer: Error userInfo: \(nsError.userInfo)")
            
            // Check for common network errors
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorCannotFindHost:
                    self.statusMessage = "Cannot find server. Check network permissions."
                case NSURLErrorNotConnectedToInternet:
                    self.statusMessage = "No internet connection"
                case NSURLErrorTimedOut:
                    self.statusMessage = "Connection timed out"
                case NSURLErrorSecureConnectionFailed:
                    self.statusMessage = "Secure connection failed (try HTTP)"
                case NSURLErrorAppTransportSecurityRequiresSecureConnection:
                    self.statusMessage = "App requires HTTPS. Check Info.plist settings."
                default:
                    break
                }
            }
        }
    }
    
    private func describeError(_ error: Error?) -> String {
        guard let error = error else { return "Unknown error" }
        
        if let nsError = error as NSError? {
            // Provide more user-friendly messages for common errors
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorCannotFindHost:
                    return "Server not found - check network permissions in System Settings"
                case NSURLErrorNotConnectedToInternet:
                    return "No internet connection"
                case NSURLErrorTimedOut:
                    return "Connection timed out"
                case NSURLErrorAppTransportSecurityRequiresSecureConnection:
                    return "Blocked by App Transport Security"
                default:
                    return "Network error: \(nsError.localizedDescription)"
                }
            }
        }
        
        return error.localizedDescription
    }
}

// MARK: - Audio Player Errors
enum AudioPlayerError: LocalizedError {
    case invalidURL
    case playbackFailed
    case notAvailable
    case networkError
    case streamUnavailable
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid stream URL"
        case .playbackFailed:
            return "Playback failed"
        case .notAvailable:
            return "Audio playback not available"
        case .networkError:
            return "Network connection error"
        case .streamUnavailable:
            return "Stream is currently unavailable"
        }
    }
}
