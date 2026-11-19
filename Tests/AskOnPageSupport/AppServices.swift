import Foundation
import Observation

@MainActor final class SidebarStore {}

/// What the service logged, for the checks that read it.
enum CraLog {
    nonisolated(unsafe) static var notes: [String] = []
    static func note(_ message: String) { notes.append(message) }
}
