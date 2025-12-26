//
//  LiveATCService.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation

/// Service for fetching ATC feeds from LiveATC.net
/// Reference: https://www.liveatc.net
/// Streams are accessed via .pls playlist files that contain the actual Icecast URL
/// Format: http://d.liveatc.net/{mount_point}
final class LiveATCService {
    static let shared = LiveATCService()
    
    private let session: URLSession
    private let baseURL = "https://www.liveatc.net"
    
    // Cache for discovered feeds
    private var feedCache: [String: [LiveATCFeed]] = [:]
    private var cacheTimestamps: [String: Date] = [:]
    private let cacheValidityDuration: TimeInterval = 3600 // 1 hour
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }
    
    /// Fetch available LiveATC feeds for an airport
    /// - Parameter icao: The ICAO code of the airport (e.g., "KLAX", "EGLL")
    /// - Returns: Array of discovered LiveATC feeds
    func fetchFeeds(for icao: String) async throws -> [LiveATCFeed] {
        let normalizedIcao = icao.uppercased()
        
        // Check cache first
        if let cached = feedCache[normalizedIcao],
           let timestamp = cacheTimestamps[normalizedIcao],
           Date().timeIntervalSince(timestamp) < cacheValidityDuration {
            return cached
        }
        
        // Fetch from LiveATC search page
        let searchURL = URL(string: "\(baseURL)/search/?icao=\(normalizedIcao)")!
        
        do {
            var request = URLRequest(url: searchURL)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                print("LiveATC: Failed to fetch search page for \(normalizedIcao)")
                return []
            }
            
            // Parse the HTML to find .pls links and feed names
            let feeds = await parseAndResolvePlsLinks(from: html, icao: normalizedIcao)
            
            // Cache results
            if !feeds.isEmpty {
                feedCache[normalizedIcao] = feeds
                cacheTimestamps[normalizedIcao] = Date()
            }
            
            return feeds
        } catch {
            print("LiveATC fetch error: \(error)")
            return []
        }
    }
    
    /// Parse LiveATC HTML and resolve .pls files to get actual stream URLs
    private func parseAndResolvePlsLinks(from html: String, icao: String) async -> [LiveATCFeed] {
        var feeds: [LiveATCFeed] = []
        var processedMounts: Set<String> = []
        
        // Find all .pls links in the HTML
        // Pattern: href="/play/something.pls" with associated feed name nearby
        let plsPattern = #"href\s*=\s*[\"'](/play/([^\"']+)\.pls)[\"']"#
        
        guard let regex = try? NSRegularExpression(pattern: plsPattern, options: .caseInsensitive) else {
            return feeds
        }
        
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: range)
        
        // Process each .pls link found
        for match in matches {
            guard let pathRange = Range(match.range(at: 1), in: html),
                  let nameRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            
            let plsPath = String(html[pathRange])
            let plsName = String(html[nameRange])
            
            // Skip if we've already processed this
            if processedMounts.contains(plsName) {
                continue
            }
            processedMounts.insert(plsName)
            
            // Fetch and parse the .pls file to get the actual stream URL
            if let feed = await fetchAndParsePlsFile(path: plsPath, plsName: plsName, icao: icao, html: html) {
                feeds.append(feed)
            }
        }
        
        return feeds.sorted { $0.feedType.sortOrder < $1.feedType.sortOrder }
    }
    
    /// Fetch a .pls playlist file and extract the stream URL
    private func fetchAndParsePlsFile(path: String, plsName: String, icao: String, html: String) async -> LiveATCFeed? {
        let plsURL = URL(string: "\(baseURL)\(path)")!
        
        do {
            var request = URLRequest(url: plsURL)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let plsContent = String(data: data, encoding: .utf8) else {
                print("LiveATC: Failed to fetch .pls file: \(path)")
                return nil
            }
            
            // Parse .pls format to extract File1=URL
            // Format:
            // [playlist]
            // File1=http://d.liveatc.net/ksfo_co
            // Title1=...
            guard let streamURL = extractStreamURL(from: plsContent) else {
                print("LiveATC: No stream URL found in .pls: \(path)")
                return nil
            }
            
            // Extract title from .pls or HTML context
            let title = extractTitle(from: plsContent) ?? extractFeedName(plsName: plsName, icao: icao, html: html)
            
            // Determine feed type from the name
            let feedType = determineFeedType(from: plsName, title: title)
            
            // Extract mount point from stream URL
            let mountPoint = streamURL.lastPathComponent
            
            return LiveATCFeed(
                id: mountPoint,
                icao: icao.uppercased(),
                name: title,
                feedType: feedType,
                streamURL: streamURL,
                mountPoint: mountPoint
            )
        } catch {
            print("LiveATC: Error fetching .pls file \(path): \(error)")
            return nil
        }
    }
    
    /// Extract stream URL from .pls file content
    private func extractStreamURL(from plsContent: String) -> URL? {
        // Look for File1=http://...
        let lines = plsContent.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("file1=") {
                let urlString = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                return URL(string: urlString)
            }
        }
        return nil
    }
    
    /// Extract title from .pls file content
    private func extractTitle(from plsContent: String) -> String? {
        let lines = plsContent.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("title1=") {
                let title = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    return title
                }
            }
        }
        return nil
    }
    
    /// Extract a human-readable feed name from context
    private func extractFeedName(plsName: String, icao: String, html: String) -> String {
        let uppercaseIcao = icao.uppercased()
        
        // Try to find the feed name in HTML near the .pls link
        // Look for patterns like: >KSFO Tower</a> or similar
        let namePattern = #">\s*([^<]*\b(?:Tower|Ground|Approach|Departure|Center|Clearance|ATIS|Combined|Del|App|Gnd|Twr|Ctr|Dep|TRACON)[^<]*)\s*</[at]"#
        
        if let regex = try? NSRegularExpression(pattern: namePattern, options: .caseInsensitive) {
            let range = NSRange(html.startIndex..., in: html)
            let matches = regex.matches(in: html, options: [], range: range)
            
            for match in matches {
                if let captureRange = Range(match.range(at: 1), in: html) {
                    let name = String(html[captureRange]).trimmingCharacters(in: .whitespaces)
                    // Check if this name is relevant to our ICAO code
                    if name.uppercased().contains(uppercaseIcao) || 
                       name.lowercased().contains(plsName.lowercased()) {
                        return name
                    }
                }
            }
        }
        
        // Fallback: create name from pls filename
        return formatFeedName(from: plsName, icao: uppercaseIcao)
    }
    
    /// Format a feed name from the .pls filename
    private func formatFeedName(from plsName: String, icao: String) -> String {
        var name = plsName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        
        // Capitalize appropriately
        let words = name.components(separatedBy: " ")
        name = words.map { word in
            let lower = word.lowercased()
            switch lower {
            case "twr", "tower": return "Tower"
            case "gnd", "ground": return "Ground"
            case "app", "approach": return "Approach"
            case "dep", "departure": return "Departure"
            case "ctr", "center": return "Center"
            case "del", "clearance": return "Clearance"
            case "atis": return "ATIS"
            case "co", "combined": return "Combined"
            case "tracon": return "TRACON"
            case "n", "north": return "North"
            case "s", "south": return "South"
            case "e", "east": return "East"
            case "w", "west": return "West"
            default:
                // Check if it's an ICAO code (4 letters starting with valid prefix)
                if word.count == 4 && word.uppercased().first?.isLetter == true {
                    return word.uppercased()
                }
                return word.capitalized
            }
        }.joined(separator: " ")
        
        // Ensure ICAO is included
        if !name.uppercased().contains(icao) {
            name = "\(icao) \(name)"
        }
        
        return name
    }
    
    /// Determine the feed type from name/title
    private func determineFeedType(from plsName: String, title: String) -> ATCFeedType {
        let combined = (plsName + " " + title).lowercased()
        
        if combined.contains("tower") || combined.contains("twr") {
            return .tower
        } else if combined.contains("ground") || combined.contains("gnd") {
            return .ground
        } else if combined.contains("approach") || combined.contains("app") || combined.contains("tracon") {
            return .approach
        } else if combined.contains("departure") || combined.contains("dep") {
            return .departure
        } else if combined.contains("center") || combined.contains("ctr") {
            return .center
        } else if combined.contains("clearance") || combined.contains("del") {
            return .clearance
        } else if combined.contains("atis") {
            return .atis
        } else if combined.contains("combined") || combined.contains("_co") {
            return .tower // Combined feeds often include tower
        }
        
        return .other
    }
    
    /// Verify if a LiveATC feed stream is available
    func verifyFeed(_ feed: LiveATCFeed) async -> Bool {
        do {
            var request = URLRequest(url: feed.streamURL)
            request.httpMethod = "HEAD"
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 5
            
            let (_, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200 || 
                       httpResponse.statusCode == 302 ||
                       httpResponse.statusCode < 400
            }
            return false
        } catch {
            return false
        }
    }
    
    /// Clear the feed cache
    func clearCache() {
        feedCache.removeAll()
        cacheTimestamps.removeAll()
    }
}

// MARK: - ATCFeedType Extension for Sorting
extension ATCFeedType {
    var sortOrder: Int {
        switch self {
        case .tower: return 0
        case .ground: return 1
        case .approach: return 2
        case .departure: return 3
        case .center: return 4
        case .clearance: return 5
        case .atis: return 6
        case .other: return 7
        }
    }
}
