//
//  AddATCFeedSheet.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI
import SwiftData

/// Sheet for adding a new ATC feed - either from LiveATC or manually
struct AddATCFeedSheet: View {
    let airport: Airport
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                LiveATCBrowserView(airport: airport, onFeedAdded: { dismiss() })
                    .tabItem {
                        Label("LiveATC", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .tag(0)
                
                ManualFeedEntryView(airport: airport, onFeedAdded: { dismiss() })
                    .tabItem {
                        Label("Manual", systemImage: "pencil")
                    }
                    .tag(1)
            }
            .navigationTitle("Add ATC Feed")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 450)
        #endif
    }
}

// MARK: - LiveATC Browser View
struct LiveATCBrowserView: View {
    let airport: Airport
    let onFeedAdded: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Query private var existingFeeds: [ATCFeed]
    
    @State private var availableFeeds: [LiveATCFeed] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    private var existingMountPoints: Set<String> {
        Set(existingFeeds
            .filter { $0.airportIcao == airport.icao }
            .compactMap { extractMountPoint(from: $0.streamURLString) })
    }
    
    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Finding available feeds...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView {
                    Label("Unable to Load Feeds", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") {
                        Task { await loadFeeds() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if availableFeeds.isEmpty {
                ContentUnavailableView {
                    Label("No Feeds Found", systemImage: "antenna.radiowaves.left.and.right.slash")
                } description: {
                    Text("No LiveATC feeds found for \(airport.shortCode). Try adding a feed manually.")
                }
            } else {
                List {
                    Section {
                        ForEach(availableFeeds) { feed in
                            LiveATCFeedRowView(
                                feed: feed,
                                isAlreadyAdded: existingMountPoints.contains(feed.mountPoint),
                                onAdd: { addFeed(feed) }
                            )
                        }
                    } header: {
                        Text("Available from LiveATC.net")
                    } footer: {
                        Text("Feeds are provided by LiveATC.net volunteer broadcasters")
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
            }
        }
        .task {
            await loadFeeds()
        }
    }
    
    private func loadFeeds() async {
        isLoading = true
        errorMessage = nil
        
        do {
            availableFeeds = try await LiveATCService.shared.fetchFeeds(for: airport.icao)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    private func addFeed(_ feed: LiveATCFeed) {
        let atcFeed = feed.toATCFeed()
        modelContext.insert(atcFeed)
        onFeedAdded()
    }
    
    private func extractMountPoint(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let mount = components.queryItems?.first(where: { $0.name == "mount" })?.value else {
            return nil
        }
        return mount
    }
}

// MARK: - LiveATC Feed Row View
struct LiveATCFeedRowView: View {
    let feed: LiveATCFeed
    let isAlreadyAdded: Bool
    let onAdd: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Feed Type Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: feed.feedType.icon)
                    .foregroundStyle(Color.accentColor)
            }
            
            // Feed Info
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.name)
                    .font(.headline)
                
                Text(feed.feedType.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Add Button
            if isAlreadyAdded {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button {
                    onAdd()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Manual Feed Entry View
struct ManualFeedEntryView: View {
    let airport: Airport
    let onFeedAdded: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    
    @State private var name = ""
    @State private var streamURL = ""
    @State private var feedType: ATCFeedType = .tower
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !streamURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        URL(string: streamURL) != nil
    }
    
    var body: some View {
        Form {
            Section {
                TextField("Feed Name", text: $name)
                    .textContentType(.name)
                
                Picker("Feed Type", selection: $feedType) {
                    ForEach(ATCFeedType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon)
                            .tag(type)
                    }
                }
            } header: {
                Text("Feed Details")
            } footer: {
                Text("Choose a descriptive name like '\(airport.shortCode) Tower' or 'Ground Control'")
            }
            
            Section {
                TextField("Stream URL", text: $streamURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
            } header: {
                Text("Stream URL")
            } footer: {
                Text("Enter the direct URL to the audio stream (MP3, AAC, or other supported format)")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Where to find ATC streams:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Label("LiveATC.net", systemImage: "globe")
                        Label("Audio feeds from airport enthusiast communities", systemImage: "person.3")
                        Label("Local aviation club streams", systemImage: "airplane.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            
            Section {
                Button {
                    addFeed()
                } label: {
                    HStack {
                        Spacer()
                        Label("Add Feed", systemImage: "plus.circle.fill")
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(!isValid)
            }
        }
        .formStyle(.grouped)
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func addFeed() {
        guard let url = URL(string: streamURL.trimmingCharacters(in: .whitespaces)) else {
            errorMessage = "Invalid URL format"
            showingError = true
            return
        }
        
        let feed = ATCFeed(
            airportIcao: airport.icao,
            name: name.trimmingCharacters(in: .whitespaces),
            streamURL: url,
            feedType: feedType
        )
        
        modelContext.insert(feed)
        onFeedAdded()
    }
}

#Preview {
    AddATCFeedSheet(airport: .sampleLAX)
        .modelContainer(for: ATCFeed.self, inMemory: true)
}
