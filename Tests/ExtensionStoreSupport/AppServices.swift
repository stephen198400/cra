import Foundation

enum AppPaths {
    static var supportDir: URL = {
        guard let path = ProcessInfo.processInfo.environment["CRA_DATA_DIR"] else {
            fatalError("Extension store tests require CRA_DATA_DIR")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }()

    static var chromiumCache: URL { supportDir.appendingPathComponent("Chromium", isDirectory: true) }
    static func file(_ name: String) -> URL { supportDir.appendingPathComponent(name) }
}

enum CraLog {
    static func note(_ message: String) {}
}
