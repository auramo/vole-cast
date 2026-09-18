import Foundation

/// The "3 days ago · 42 min" line under an episode title, shared by the
/// preview, detail and episode screens so they can't drift apart.
enum EpisodeSubtitle {
    static func text(published: Date?, duration: TimeInterval?) -> String {
        var parts: [String] = []
        if let published {
            parts.append(published.formatted(.relative(presentation: .named)))
        }
        if let duration, duration > 0 {
            parts.append(
                Duration.seconds(duration)
                    .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
            )
        }
        return parts.joined(separator: " · ")
    }
}
