//
//  AviaryApp.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI
import SwiftData

@main
struct AviaryApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ATCFeed.self,
            FlightCacheEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}
