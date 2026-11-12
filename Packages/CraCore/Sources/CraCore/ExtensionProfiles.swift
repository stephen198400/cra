import Foundation

/// extension-profiles.json: the Chromium profile folders ("Default", "Profile <id>") each folder in
/// Extensions/ loads in, by folder name. Chromium loads those folders with --load-extension, which
/// installs them in every profile; Cra's CEF build skips a profile the list leaves out
/// (--cra-load-extension-profiles), so such an extension is not installed there at all. A folder
/// with no list loads in every profile, as every one did before GitHub #131. Lists in it came from
/// imports of other browsers' profiles, which From no longer has.
public struct ExtensionProfiles: Codable, Equatable, Sendable {
    public var folders: [String: [String]]

    public init(folders: [String: [String]] = [:]) {
        self.folders = folders
    }

    /// The profile folders `folder` loads in; nil for every profile.
    public func profiles(ofFolder folder: String) -> Set<String>? { folders[folder].map(Set.init) }

    public func loads(folder: String, inProfile profile: String) -> Bool { profiles(ofFolder: folder)?.contains(profile) ?? true }

    public mutating func remove(folder: String) { folders[folder] = nil }

    /// --cra-load-extension-profiles for the --load-extension `folders` in that order: each one's
    /// profiles joined by "|", "*" for every profile. nil when every folder loads everywhere.
    public func commandLineValue(forFolders names: [String]) -> String? {
        let values = names.map { name in folders[name].map { $0.sorted().joined(separator: "|") } ?? "*" }
        return values.allSatisfy { $0 == "*" } ? nil : values.joined(separator: ",")
    }

    public init(from decoder: Decoder) throws {
        folders = try decoder.singleValueContainer().decode([String: [String]].self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(folders)
    }
}
