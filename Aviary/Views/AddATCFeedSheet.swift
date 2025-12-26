//
//  AddATCFeedSheet.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI
import SwiftData

/// Sheet for adding a new ATC feed
struct AddATCFeedSheet: View {
    let airport: Airport
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
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
        NavigationStack {
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
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addFeed()
                    }
                    .disabled(!isValid)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 350)
        #endif
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
        dismiss()
    }
}

#Preview {
    AddATCFeedSheet(airport: .sampleLAX)
        .modelContainer(for: ATCFeed.self, inMemory: true)
}

