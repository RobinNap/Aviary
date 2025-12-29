//
//  SettingsView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI

/// Settings view for configuring OpenSky Network data provider
struct SettingsView: View {
    private let aircraftSettings = AircraftSettings.shared
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
                    #if os(macOS)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(AircraftProviderType.allCases) { provider in
                            ProviderSelectionRow(
                                provider: provider,
                                isSelected: selectedProvider == provider
                            ) {
                                selectedProvider = provider
                                loadCredentials(for: provider)
                                
                                if provider.requiresAuth {
                                    showingCredentials = true
                                } else {
                                    saveProvider()
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    #else
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
                    #endif
                } header: {
                    Label("Data Source", systemImage: "airplane")
                        .font(.headline)
                } footer: {
                    Text("OpenSky Network provides free real-time aircraft tracking data. Create a free account and API client at opensky-network.org for faster updates (1 request/second vs 1 per 10 seconds).")
                        .font(.caption)
                }
                
                if selectedProvider.requiresAuth {
                    Section {
                        if showingCredentials {
                            VStack(alignment: .leading, spacing: 12) {
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
                                
                                HStack {
                                    Spacer()
                                    Button {
                                        saveProvider()
                                    } label: {
                                        HStack(spacing: 6) {
                                            if isSaving {
                                                ProgressView()
                                                    .scaleEffect(0.7)
                                                    .frame(width: 12, height: 12)
                                            } else {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 12))
                                            }
                                            Text(isSaving ? "Verifying..." : "Save & Verify")
                                        }
                                        .frame(minWidth: 140)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isSaving || !hasValidCredentials)
                                }
                                .padding(.top, 4)
                            }
                            .padding(.vertical, 4)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    showingCredentials = true
                                } label: {
                                    HStack {
                                        Image(systemName: "key.fill")
                                            .font(.system(size: 13))
                                        Text("Configure Credentials")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.bordered)
                                
                                if hasStoredCredentials {
                                    Button(role: .destructive) {
                                        clearCredentials()
                                    } label: {
                                        HStack {
                                            Image(systemName: "trash")
                                                .font(.system(size: 13))
                                            Text("Clear Credentials")
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Label("Authentication", systemImage: "lock.shield")
                            .font(.headline)
                    } footer: {
                        Text("Create a free account at opensky-network.org and create an API client to get Client ID and Client Secret. This gives you 1 request per second instead of 1 per 10 seconds. Legacy username/password authentication is also supported but deprecated.")
                            .font(.caption)
                    }
                }
                
                Section {
                    HStack {
                        Label("Current Mode", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                        Spacer()
                        ProviderStatusBadge(status: providerStatus, isConfigured: hasStoredCredentials || !selectedProvider.requiresAuth)
                    }
                    .padding(.vertical, 2)
                    
                    HStack {
                        Label("Rate Limit", systemImage: "clock")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(selectedProvider == .openSkyAuthenticated && hasStoredCredentials ? "1 request/second" : "1 request/10 seconds")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Label("Status", systemImage: "info.circle")
                        .font(.headline)
                }
                
                Section {
                    Link(destination: URL(string: "https://opensky-network.org/")!) {
                        HStack {
                            Image(systemName: "globe")
                            Text("OpenSky Network Website")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("Resources", systemImage: "link")
                        .font(.headline)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Built by")
                                .foregroundStyle(.secondary)
                            Text("Lumon Labs / Robin Nap")
                        }
                        .font(.subheadline)
                        
                        HStack {
                            Text("Icon design by")
                                .foregroundStyle(.secondary)
                            Text("Ronald Vermeulen")
                        }
                        .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Credits", systemImage: "heart.fill")
                        .font(.headline)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 500, idealWidth: 600, maxWidth: 700)
            .padding()
            #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #endif
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
        aircraftSettings.getCredentials(for: selectedProvider) != nil
    }
    
    private var providerStatus: String {
        if selectedProvider.requiresAuth {
            if hasStoredCredentials {
                return "Authenticated"
            } else {
                return "Not Configured"
            }
        } else {
            return "Anonymous"
        }
    }
    
    private func loadCredentials(for provider: AircraftProviderType) {
        if let stored = aircraftSettings.getCredentials(for: provider) {
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
                    
                    // Verify credentials before saving
                    // Support both OAuth2 (clientId/clientSecret) and legacy (username/password)
                    let hasOAuth2 = !(credentials["clientId"]?.isEmpty ?? true) && !(credentials["clientSecret"]?.isEmpty ?? true)
                    let hasLegacy = !(credentials["username"]?.isEmpty ?? true) && !(credentials["password"]?.isEmpty ?? true)
                    
                    guard hasOAuth2 || hasLegacy else {
                        errorMessage = "Please provide either Client ID and Client Secret (OAuth2) or Username and Password (legacy)"
                        showingError = true
                        isSaving = false
                        return
                    }
                    
                    // Test credentials with OpenSky API
                    let testProvider = OpenSkyAircraftProvider(authenticated: true)
                    let isValid: Bool
                    
                    if hasOAuth2, let clientId = credentials["clientId"], let clientSecret = credentials["clientSecret"] {
                        isValid = try await testProvider.testCredentials(clientId: clientId, clientSecret: clientSecret)
                    } else if hasLegacy, let username = credentials["username"], let password = credentials["password"] {
                        // Legacy Basic Auth - for now just check format, actual test would need Basic Auth support
                        isValid = !username.isEmpty && !password.isEmpty
                    } else {
                        isValid = false
                    }
                    
                    if !isValid {
                        if hasOAuth2 {
                            errorMessage = "Invalid credentials. Please check your Client ID and Client Secret. Make sure you have created an API client at opensky-network.org."
                        } else {
                            errorMessage = "Invalid credentials. Please check your username and password. Note: Basic Auth is deprecated. Use OAuth2 (Client ID/Secret) instead."
                        }
                        showingError = true
                        isSaving = false
                        return
                    }
                    
                    // Credentials are valid, save them
                    aircraftSettings.saveCredentials(credentials, for: selectedProvider)
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
                
                aircraftSettings.selectedProvider = selectedProvider
                
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
        aircraftSettings.clearCredentials(for: selectedProvider)
        credentials = [:]
        showingCredentials = false
        
        // Reset to anonymous if current provider requires auth
        if aircraftSettings.selectedProvider == selectedProvider && selectedProvider.requiresAuth {
            aircraftSettings.selectedProvider = .openSky
            selectedProvider = .openSky
            try? AircraftProviderManager.shared.switchProvider(to: .openSky, credentials: nil)
            NotificationCenter.default.post(name: .aircraftProviderChanged, object: nil)
        }
    }
}

// MARK: - Helper Views

#if os(macOS)
/// Radio button style provider selection row for macOS
struct ProviderSelectionRow: View {
    let provider: AircraftProviderType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                // Radio button indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.secondary, lineWidth: 2)
                        .frame(width: 18, height: 18)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 10, height: 10)
                    }
                }
                .padding(.top, 2)
                
                // Provider info
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    
                    Text(provider.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Status indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
    }
}
#endif

/// Status badge for provider status
struct ProviderStatusBadge: View {
    let status: String
    let isConfigured: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConfigured ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            
            Text(status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isConfigured ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
        )
    }
}

struct AuthFieldView: View {
    let field: AuthField
    @Binding var value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Group {
                if field.isSecure {
                    SecureField("", text: $value)
                } else {
                    TextField("", text: $value)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
            }
            .textFieldStyle(.roundedBorder)
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
