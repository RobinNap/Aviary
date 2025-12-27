//
//  ContentView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        RootSplitView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ATCFeed.self, FlightCacheEntry.self], inMemory: true)
}
