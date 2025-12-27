//
//  SettingsView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI

/// Settings view for configuring aircraft data providers
struct SettingsView: View {
    private let settings = AircraftSettings.shared
    @State private var selectedProvider: AircraftProviderType
    @State private var credentials: [String: String] = [:]
    @State private var showingCredentials = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isSaving = false
    
    @Environment(\.dismiss) private var dismiss
    
    init() {
        _selectedProvider = State(initialValue: AircraftSettings.shared.selectedProvider)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Data Source", selection: $selectedProvider) {
                        ForEach(AircraftProviderType.allCases) { provider in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(provider.displayName)
                                    .font(.body)
                                Text(provider.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedProvider) { _, newValue in
                        loadCredentials(for: newValue)
                        if newValue.requiresAuth {
                            showingCredentials = true
                        } else {
                            saveProvider()
                        }
                    }
                } header: {
                    Text("Aircraft Data Provider")
                } footer: {
                    Text("Select the data source for real-time aircraft tracking. Some providers require API keys or authentication.")
                }
                
                if selectedProvider.requiresAuth {
                    Section {
                        if showingCredentials {
                            ForEach(selectedProvider.authFields.indices, id: \.self) { index in
                                AuthFieldView(
                                    field: selectedProvider.authFields[index],
                                    value: Binding(
                                        get: { credentials[selectedProvider.authFields[index].key] ?? "" },
                                        set: { newValue in
                                            credentials[selectedProvider.authFields[index].key] = newValue
                                        }
                                    )
                                )
                            }
                            
                            Button {
                                saveProvider()
                            } label: {
                                HStack {
                                    if isSaving {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                    Text("Save Credentials")
                                }
                            }
                            .disabled(isSaving || !hasValidCredentials)
                        } else {
                            Button {
                                showingCredentials = true
                            } label: {
                                HStack {
                                    Image(systemName: "key.fill")
                                    Text("Configure Credentials")
                                }
                            }
                            
                            if hasStoredCredentials {
                                Button(role: .destructive) {
                                    clearCredentials()
                                } label: {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Clear Credentials")
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Authentication")
                    } footer: {
                        authenticationFooter
                    }
                }
                
                Section {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Current Provider")
                        Spacer()
                        Text(providerStatus)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Status")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
            .onAppear {
                loadCredentials(for: selectedProvider)
            }
        }
    }
    
    private var hasValidCredentials: Bool {
        let requiredFields = selectedProvider.authFields.map { $0.key }
        return requiredFields.allSatisfy { !(credentials[$0]?.isEmpty ?? true) }
    }
    
    private var hasStoredCredentials: Bool {
        settings.getCredentials(for: selectedProvider) != nil
    }
    
    private var providerStatus: String {
        if selectedProvider.requiresAuth {
            if hasStoredCredentials {
                return "Configured"
            } else {
                return "Not Configured"
            }
        } else {
            return "Active"
        }
    }
    
    @ViewBuilder
    private var authenticationFooter: some View {
        switch selectedProvider {
        case .openSky:
            EmptyView()
        case .openSkyAuthenticated:
            Text("Create a free account at opensky-network.org to get 1 request per second instead of 1 per 10 seconds.")
        case .flightradar24:
            Text("Requires a Flightradar24 API subscription. Visit flightradar24.com for API access.")
        }
    }
    
    private func loadCredentials(for provider: AircraftProviderType) {
        if let stored = settings.getCredentials(for: provider) {
            credentials = stored
            showingCredentials = true
        } else {
            credentials = [:]
            showingCredentials = false
        }
    }
    
    private func saveProvider() {
        isSaving = true
        errorMessage = nil
        
        Task { @MainActor in
            do {
                if selectedProvider.requiresAuth {
                    guard hasValidCredentials else {
                        errorMessage = "Please fill in all required fields"
                        showingError = true
                        isSaving = false
                        return
                    }
                    
                    try AircraftProviderManager.shared.switchProvider(
                        to: selectedProvider,
                        credentials: credentials
                    )
                } else {
                    try AircraftProviderManager.shared.switchProvider(
                        to: selectedProvider,
                        credentials: nil
                    )
                }
                
                // Reload provider in view model
                NotificationCenter.default.post(name: .aircraftProviderChanged, object: nil)
                
                isSaving = false
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
                isSaving = false
            }
        }
    }
    
    private func clearCredentials() {
        settings.clearCredentials(for: selectedProvider)
        credentials = [:]
        showingCredentials = false
        
        // Reset to default if current provider
        if settings.selectedProvider == selectedProvider {
            settings.selectedProvider = .openSky
            selectedProvider = .openSky
            try? AircraftProviderManager.shared.switchProvider(to: .openSky, credentials: nil)
            NotificationCenter.default.post(name: .aircraftProviderChanged, object: nil)
        }
    }
}

// MARK: - Helper View
struct AuthFieldView: View {
    let field: AuthField
    @Binding var value: String
    
    var body: some View {
        if field.isSecure {
            SecureField(field.label, text: $value)
        } else {
            TextField(field.label, text: $value)
                .autocorrectionDisabled()
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let aircraftProviderChanged = Notification.Name("aircraftProviderChanged")
}

#Preview {
    SettingsView()
}

