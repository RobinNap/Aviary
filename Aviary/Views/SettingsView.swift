//
//  SettingsView.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import SwiftUI

/// Settings view for configuring aircraft data providers and flight data sources
struct SettingsView: View {
    private let aircraftSettings = AircraftSettings.shared
    private let flightSettings = FlightServiceSettings.shared
    @State private var selectedProvider: AircraftProviderType
    @State private var selectedFlightService: FlightServiceType
    @State private var credentials: [String: String] = [:]
    @State private var showingCredentials = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isSaving = false
    
    @Environment(\.dismiss) private var dismiss
    
    init() {
        _selectedProvider = State(initialValue: AircraftSettings.shared.selectedProvider)
        _selectedFlightService = State(initialValue: FlightServiceSettings.shared.selectedService)
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
                    Label("Aircraft Data Provider", systemImage: "airplane")
                        .font(.headline)
                } footer: {
                    Text("Select the data source for real-time aircraft tracking. Some providers require API keys or authentication.")
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
                                            Text("Save Credentials")
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
                        authenticationFooter
                            .font(.caption)
                    }
                }
                
                Section {
                    HStack {
                        Label("Current Provider", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                        Spacer()
                        ProviderStatusBadge(status: providerStatus, isConfigured: hasStoredCredentials || !selectedProvider.requiresAuth)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Label("Status", systemImage: "info.circle")
                        .font(.headline)
                }
                
                // Flight Data Source Section
                Section {
                    #if os(macOS)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(FlightServiceType.allCases) { service in
                            FlightServiceSelectionRow(
                                service: service,
                                isSelected: selectedFlightService == service,
                                isConfigured: hasFlightServiceCredentials(for: service)
                            ) {
                                selectedFlightService = service
                                saveFlightService()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    #else
                    Picker("Flight Data Source", selection: $selectedFlightService) {
                        ForEach(FlightServiceType.allCases) { service in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(service.displayName)
                                    .font(.body)
                                Text(service.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if service.requiresAuth && !hasFlightServiceCredentials(for: service) {
                                    Text("⚠️ Requires API key in Aircraft Data Provider settings")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .tag(service)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedFlightService) { _, _ in
                        saveFlightService()
                    }
                    #endif
                } header: {
                    Label("Flight Data Source", systemImage: "airplane.departure")
                        .font(.headline)
                } footer: {
                    if selectedFlightService == .flightradar24 {
                        Text("Flightradar24 requires an API key. Configure it in the Aircraft Data Provider section above using the same credentials.")
                            .font(.caption)
                    } else {
                        Text("Select the data source for arrivals and departures. Some sources have rate limits.")
                            .font(.caption)
                    }
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
        case .aviationstack:
            Text("Get a free API key at aviationstack.com. Free plan includes 100 requests/month. Paid plans start at $49.99/month.")
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
        
        // Reset to default if current provider
        if aircraftSettings.selectedProvider == selectedProvider {
            aircraftSettings.selectedProvider = .openSky
            selectedProvider = .openSky
            try? AircraftProviderManager.shared.switchProvider(to: .openSky, credentials: nil)
            NotificationCenter.default.post(name: .aircraftProviderChanged, object: nil)
        }
    }
    
    private func saveFlightService() {
        flightSettings.selectedService = selectedFlightService
        
        // Update Flightradar24 service credentials if needed
        if selectedFlightService == .flightradar24 {
            Flightradar24FlightService.shared.updateCredentials()
        }
        
        NotificationCenter.default.post(name: .flightServiceChanged, object: nil)
    }
    
    private func hasFlightServiceCredentials(for service: FlightServiceType) -> Bool {
        if service == .flightradar24 {
            return aircraftSettings.getCredentials(for: .flightradar24) != nil
        }
        return true // OpenSky doesn't require credentials
    }
}

// MARK: - Helper Views

#if os(macOS)
/// Radio button style flight service selection row for macOS
struct FlightServiceSelectionRow: View {
    let service: FlightServiceType
    let isSelected: Bool
    let isConfigured: Bool
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
                
                // Service info
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    
                    Text(service.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if service.requiresAuth && !isConfigured {
                        Text("⚠️ Requires API key in Aircraft Data Provider settings")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
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
    static let flightServiceChanged = Notification.Name("flightServiceChanged")
}

// MARK: - Flight Service Selection Row (macOS)
#if os(macOS)
struct FlightServiceSelectionRow: View {
    let service: FlightServiceType
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
                
                // Service info
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    
                    Text(service.description)
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

#Preview {
    SettingsView()
}

