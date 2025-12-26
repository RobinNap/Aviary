//
//  AirportCatalog.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import Combine

/// Service for searching and loading airport data
@MainActor
final class AirportCatalog: ObservableObject {
    static let shared = AirportCatalog()
    
    @Published private(set) var airports: [Airport] = []
    @Published private(set) var searchResults: [Airport] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    private var searchTask: Task<Void, Never>?
    
    private init() {
        Task {
            await loadAirports()
        }
    }
    
    /// Load airports from bundled JSON
    func loadAirports() async {
        isLoading = true
        defer { isLoading = false }
        
        // First try to load from bundled JSON
        if let url = Bundle.main.url(forResource: "airports_min", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                airports = try JSONDecoder().decode([Airport].self, from: data)
                return
            } catch {
                self.error = error
                print("Error loading airports from bundle: \(error)")
            }
        }
        
        // Fallback to embedded sample data
        airports = Self.embeddedAirports
    }
    
    /// Search airports by query (ICAO, IATA, name, or city)
    func search(query: String) {
        searchTask?.cancel()
        
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        
        searchTask = Task {
            // Small delay for debouncing
            try? await Task.sleep(nanoseconds: 150_000_000)
            
            guard !Task.isCancelled else { return }
            
            let results = airports.filter { airport in
                airport.icao.lowercased().contains(trimmed) ||
                (airport.iata?.lowercased().contains(trimmed) ?? false) ||
                airport.name.lowercased().contains(trimmed) ||
                (airport.city?.lowercased().contains(trimmed) ?? false)
            }
            .prefix(25)
            
            guard !Task.isCancelled else { return }
            
            searchResults = Array(results)
        }
    }
    
    /// Get airport by ICAO code
    func airport(byIcao icao: String) -> Airport? {
        airports.first { $0.icao.uppercased() == icao.uppercased() }
    }
    
    /// Get airport by IATA code
    func airport(byIata iata: String) -> Airport? {
        airports.first { $0.iata?.uppercased() == iata.uppercased() }
    }
    
    // MARK: - Embedded Sample Data
    /// Fallback airport data when JSON is not available
    private static let embeddedAirports: [Airport] = [
        // Major US Airports
        Airport(icao: "KLAX", iata: "LAX", name: "Los Angeles International Airport", city: "Los Angeles", country: "United States", latitude: 33.9425, longitude: -118.4081, elevation: 125, timezone: "America/Los_Angeles"),
        Airport(icao: "KJFK", iata: "JFK", name: "John F. Kennedy International Airport", city: "New York", country: "United States", latitude: 40.6413, longitude: -73.7781, elevation: 13, timezone: "America/New_York"),
        Airport(icao: "KORD", iata: "ORD", name: "O'Hare International Airport", city: "Chicago", country: "United States", latitude: 41.9742, longitude: -87.9073, elevation: 672, timezone: "America/Chicago"),
        Airport(icao: "KATL", iata: "ATL", name: "Hartsfield-Jackson Atlanta International Airport", city: "Atlanta", country: "United States", latitude: 33.6407, longitude: -84.4277, elevation: 1026, timezone: "America/New_York"),
        Airport(icao: "KDFW", iata: "DFW", name: "Dallas/Fort Worth International Airport", city: "Dallas", country: "United States", latitude: 32.8998, longitude: -97.0403, elevation: 607, timezone: "America/Chicago"),
        Airport(icao: "KDEN", iata: "DEN", name: "Denver International Airport", city: "Denver", country: "United States", latitude: 39.8561, longitude: -104.6737, elevation: 5431, timezone: "America/Denver"),
        Airport(icao: "KSFO", iata: "SFO", name: "San Francisco International Airport", city: "San Francisco", country: "United States", latitude: 37.6213, longitude: -122.3790, elevation: 13, timezone: "America/Los_Angeles"),
        Airport(icao: "KLAS", iata: "LAS", name: "Harry Reid International Airport", city: "Las Vegas", country: "United States", latitude: 36.0840, longitude: -115.1537, elevation: 2181, timezone: "America/Los_Angeles"),
        Airport(icao: "KMIA", iata: "MIA", name: "Miami International Airport", city: "Miami", country: "United States", latitude: 25.7959, longitude: -80.2870, elevation: 8, timezone: "America/New_York"),
        Airport(icao: "KSEA", iata: "SEA", name: "Seattle-Tacoma International Airport", city: "Seattle", country: "United States", latitude: 47.4502, longitude: -122.3088, elevation: 433, timezone: "America/Los_Angeles"),
        Airport(icao: "KPHX", iata: "PHX", name: "Phoenix Sky Harbor International Airport", city: "Phoenix", country: "United States", latitude: 33.4373, longitude: -112.0078, elevation: 1135, timezone: "America/Phoenix"),
        Airport(icao: "KEWR", iata: "EWR", name: "Newark Liberty International Airport", city: "Newark", country: "United States", latitude: 40.6895, longitude: -74.1745, elevation: 18, timezone: "America/New_York"),
        Airport(icao: "KBOS", iata: "BOS", name: "Boston Logan International Airport", city: "Boston", country: "United States", latitude: 42.3656, longitude: -71.0096, elevation: 20, timezone: "America/New_York"),
        
        // Major European Airports
        Airport(icao: "EGLL", iata: "LHR", name: "Heathrow Airport", city: "London", country: "United Kingdom", latitude: 51.4700, longitude: -0.4543, elevation: 83, timezone: "Europe/London"),
        Airport(icao: "LFPG", iata: "CDG", name: "Charles de Gaulle Airport", city: "Paris", country: "France", latitude: 49.0097, longitude: 2.5479, elevation: 392, timezone: "Europe/Paris"),
        Airport(icao: "EDDF", iata: "FRA", name: "Frankfurt Airport", city: "Frankfurt", country: "Germany", latitude: 50.0379, longitude: 8.5622, elevation: 364, timezone: "Europe/Berlin"),
        Airport(icao: "EHAM", iata: "AMS", name: "Amsterdam Airport Schiphol", city: "Amsterdam", country: "Netherlands", latitude: 52.3086, longitude: 4.7639, elevation: -11, timezone: "Europe/Amsterdam"),
        Airport(icao: "LEMD", iata: "MAD", name: "Adolfo Suárez Madrid–Barajas Airport", city: "Madrid", country: "Spain", latitude: 40.4983, longitude: -3.5676, elevation: 1998, timezone: "Europe/Madrid"),
        Airport(icao: "LIRF", iata: "FCO", name: "Leonardo da Vinci–Fiumicino Airport", city: "Rome", country: "Italy", latitude: 41.8003, longitude: 12.2389, elevation: 13, timezone: "Europe/Rome"),
        Airport(icao: "EDDM", iata: "MUC", name: "Munich Airport", city: "Munich", country: "Germany", latitude: 48.3537, longitude: 11.7750, elevation: 1487, timezone: "Europe/Berlin"),
        Airport(icao: "EGKK", iata: "LGW", name: "Gatwick Airport", city: "London", country: "United Kingdom", latitude: 51.1537, longitude: -0.1821, elevation: 202, timezone: "Europe/London"),
        Airport(icao: "LEBL", iata: "BCN", name: "Barcelona–El Prat Airport", city: "Barcelona", country: "Spain", latitude: 41.2971, longitude: 2.0785, elevation: 12, timezone: "Europe/Madrid"),
        Airport(icao: "LSZH", iata: "ZRH", name: "Zurich Airport", city: "Zurich", country: "Switzerland", latitude: 47.4647, longitude: 8.5492, elevation: 1416, timezone: "Europe/Zurich"),
        
        // Major Asian Airports
        Airport(icao: "VHHH", iata: "HKG", name: "Hong Kong International Airport", city: "Hong Kong", country: "Hong Kong", latitude: 22.3080, longitude: 113.9185, elevation: 28, timezone: "Asia/Hong_Kong"),
        Airport(icao: "RJTT", iata: "HND", name: "Tokyo Haneda Airport", city: "Tokyo", country: "Japan", latitude: 35.5494, longitude: 139.7798, elevation: 35, timezone: "Asia/Tokyo"),
        Airport(icao: "WSSS", iata: "SIN", name: "Singapore Changi Airport", city: "Singapore", country: "Singapore", latitude: 1.3644, longitude: 103.9915, elevation: 22, timezone: "Asia/Singapore"),
        Airport(icao: "RKSI", iata: "ICN", name: "Incheon International Airport", city: "Seoul", country: "South Korea", latitude: 37.4602, longitude: 126.4407, elevation: 23, timezone: "Asia/Seoul"),
        Airport(icao: "ZBAA", iata: "PEK", name: "Beijing Capital International Airport", city: "Beijing", country: "China", latitude: 40.0799, longitude: 116.6031, elevation: 116, timezone: "Asia/Shanghai"),
        Airport(icao: "ZSPD", iata: "PVG", name: "Shanghai Pudong International Airport", city: "Shanghai", country: "China", latitude: 31.1443, longitude: 121.8083, elevation: 13, timezone: "Asia/Shanghai"),
        Airport(icao: "OMDB", iata: "DXB", name: "Dubai International Airport", city: "Dubai", country: "United Arab Emirates", latitude: 25.2528, longitude: 55.3644, elevation: 62, timezone: "Asia/Dubai"),
        Airport(icao: "VTBS", iata: "BKK", name: "Suvarnabhumi Airport", city: "Bangkok", country: "Thailand", latitude: 13.6900, longitude: 100.7501, elevation: 5, timezone: "Asia/Bangkok"),
        
        // Major Australian/Oceania Airports
        Airport(icao: "YSSY", iata: "SYD", name: "Sydney Kingsford Smith Airport", city: "Sydney", country: "Australia", latitude: -33.9461, longitude: 151.1772, elevation: 21, timezone: "Australia/Sydney"),
        Airport(icao: "YMML", iata: "MEL", name: "Melbourne Airport", city: "Melbourne", country: "Australia", latitude: -37.6690, longitude: 144.8410, elevation: 434, timezone: "Australia/Melbourne"),
        Airport(icao: "NZAA", iata: "AKL", name: "Auckland Airport", city: "Auckland", country: "New Zealand", latitude: -37.0082, longitude: 174.7850, elevation: 23, timezone: "Pacific/Auckland"),
        
        // Major South American Airports
        Airport(icao: "SBGR", iata: "GRU", name: "São Paulo/Guarulhos International Airport", city: "São Paulo", country: "Brazil", latitude: -23.4356, longitude: -46.4731, elevation: 2459, timezone: "America/Sao_Paulo"),
        Airport(icao: "SAEZ", iata: "EZE", name: "Ministro Pistarini International Airport", city: "Buenos Aires", country: "Argentina", latitude: -34.8222, longitude: -58.5358, elevation: 67, timezone: "America/Argentina/Buenos_Aires"),
        
        // Canadian Airports
        Airport(icao: "CYYZ", iata: "YYZ", name: "Toronto Pearson International Airport", city: "Toronto", country: "Canada", latitude: 43.6777, longitude: -79.6248, elevation: 569, timezone: "America/Toronto"),
        Airport(icao: "CYVR", iata: "YVR", name: "Vancouver International Airport", city: "Vancouver", country: "Canada", latitude: 49.1967, longitude: -123.1815, elevation: 14, timezone: "America/Vancouver"),
        Airport(icao: "CYUL", iata: "YUL", name: "Montréal–Trudeau International Airport", city: "Montreal", country: "Canada", latitude: 45.4706, longitude: -73.7408, elevation: 118, timezone: "America/Toronto"),
    ]
}

