//
//  TimeFormatter.swift
//  Aviary
//
//  Created by Robin Nap on 27/12/2025.
//

import Foundation

/// Utility for formatting times in a consistent way across the app
enum TimeFormatter {
    /// Format a date as a relative time (e.g., "5 min ago", "in 2 hours")
    static func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    /// Format a date as time only (e.g., "14:30")
    static func timeOnly(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    /// Format a date as date and time (e.g., "Dec 27, 14:30")
    static func dateAndTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: date)
    }
    
    /// Format a time interval as duration (e.g., "2h 30m")
    static func duration(from interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    /// Get delay status text for a flight
    static func delayStatus(scheduled: Date?, actual: Date?) -> String? {
        guard let scheduled = scheduled, let actual = actual else { return nil }
        
        let difference = actual.timeIntervalSince(scheduled)
        
        if difference > 300 { // More than 5 minutes late
            return "Delayed \(duration(from: difference))"
        } else if difference < -300 { // More than 5 minutes early
            return "Early \(duration(from: abs(difference)))"
        }
        
        return nil
    }
}

