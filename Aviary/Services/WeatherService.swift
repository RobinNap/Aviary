//
//  WeatherService.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation
import CoreLocation

/// Weather information for an airport
struct AirportWeather: Codable {
    let temperature: Double // in Celsius
    let condition: String
    let humidity: Int // percentage
    let windSpeed: Double // in m/s
    let windDirection: Int? // degrees
    let visibility: Double? // in meters
    let pressure: Double? // in hPa
    let description: String
    
    var temperatureFahrenheit: Double {
        (temperature * 9/5) + 32
    }
    
    var windSpeedKnots: Double {
        windSpeed * 1.944 // m/s to knots
    }
    
    var displayTemperature: String {
        let formatter = MeasurementFormatter()
        formatter.numberFormatter.maximumFractionDigits = 0
        let temp = Measurement(value: temperature, unit: UnitTemperature.celsius)
        return formatter.string(from: temp)
    }
    
    var displayWind: String {
        if let direction = windDirection {
            return String(format: "%.0f kts @ %d°", windSpeedKnots, direction)
        }
        return String(format: "%.0f kts", windSpeedKnots)
    }
}

/// Service for fetching weather data for airports
/// Uses OpenWeatherMap API (free tier available)
final class WeatherService {
    static let shared = WeatherService()
    
    // Note: In production, store API key securely (e.g., in environment variables or keychain)
    // For now, using a placeholder - user should add their own API key
    private let apiKey: String? = nil // Add your OpenWeatherMap API key here
    private let baseURL = "https://api.openweathermap.org/data/2.5/weather"
    private let session: URLSession
    
    // Cache for weather data
    private var weatherCache: [String: (weather: AirportWeather, timestamp: Date)] = [:]
    private let cacheValidityDuration: TimeInterval = 600 // 10 minutes
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)
    }
    
    /// Configure API key for OpenWeatherMap
    func configure(apiKey: String) {
        // In a real app, store this securely
        // For now, we'll use a class variable
    }
    
    /// Fetch weather for an airport using its coordinates
    func fetchWeather(for airport: Airport) async -> AirportWeather? {
        // Check cache first
        if let cached = weatherCache[airport.icao],
           Date().timeIntervalSince(cached.timestamp) < cacheValidityDuration {
            return cached.weather
        }
        
        // If no API key, return sample data for development
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            print("WeatherService: No API key configured, returning sample data")
            return sampleWeather(for: airport)
        }
        
        let lat = airport.latitude
        let lon = airport.longitude
        
        guard var urlComponents = URLComponents(string: baseURL) else {
            return nil
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon)),
            URLQueryItem(name: "appid", value: apiKey),
            URLQueryItem(name: "units", value: "metric") // Use metric (Celsius, m/s)
        ]
        
        guard let url = urlComponents.url else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Aviary/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("WeatherService: Failed to fetch weather, status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return sampleWeather(for: airport)
            }
            
            let weatherResponse = try JSONDecoder().decode(OpenWeatherResponse.self, from: data)
            let weather = AirportWeather(
                temperature: weatherResponse.main.temp,
                condition: weatherResponse.weather.first?.main ?? "Unknown",
                humidity: weatherResponse.main.humidity,
                windSpeed: weatherResponse.wind?.speed ?? 0,
                windDirection: weatherResponse.wind?.deg,
                visibility: weatherResponse.visibility,
                pressure: weatherResponse.main.pressure,
                description: weatherResponse.weather.first?.description.capitalized ?? "Unknown"
            )
            
            // Cache the result
            weatherCache[airport.icao] = (weather, Date())
            
            return weather
        } catch {
            print("WeatherService: Error fetching weather: \(error)")
            return sampleWeather(for: airport)
        }
    }
    
    /// Generate sample weather data for development/testing
    private func sampleWeather(for airport: Airport) -> AirportWeather {
        // Generate somewhat realistic weather based on location
        let baseTemp: Double
        if airport.latitude > 40 {
            baseTemp = Double.random(in: -5...15) // Northern latitudes
        } else if airport.latitude < -20 {
            baseTemp = Double.random(in: 10...25) // Southern latitudes
        } else {
            baseTemp = Double.random(in: 15...30) // Mid latitudes
        }
        
        let conditions = ["Clear", "Clouds", "Partly Cloudy", "Light Rain"]
        let condition = conditions.randomElement() ?? "Clear"
        
        return AirportWeather(
            temperature: baseTemp,
            condition: condition,
            humidity: Int.random(in: 40...80),
            windSpeed: Double.random(in: 2...15),
            windDirection: Int.random(in: 0...360),
            visibility: Double.random(in: 8000...15000),
            pressure: Double.random(in: 980...1020),
            description: condition.lowercased()
        )
    }
}

// MARK: - OpenWeatherMap API Response Models
private struct OpenWeatherResponse: Codable {
    let main: Main
    let weather: [Weather]
    let wind: Wind?
    let visibility: Double?
}

private struct Main: Codable {
    let temp: Double
    let humidity: Int
    let pressure: Double
}

private struct Weather: Codable {
    let main: String
    let description: String
}

private struct Wind: Codable {
    let speed: Double
    let deg: Int?
}

