import CraCore
import Foundation
import Testing

/// Extensions and sign-ins follow the Arc profile a space was on (GitHub #131).
struct ExtensionProfilesTests {
    @Test func aFolderWithoutAListLoadsEverywhere() {
        let p = ExtensionProfiles(folders: ["a": ["Profile 1"]])
        #expect(p.loads(folder: "b", inProfile: "Default") && p.profiles(ofFolder: "b") == nil)
        #expect(p.loads(folder: "a", inProfile: "Profile 1") && !p.loads(folder: "a", inProfile: "Default"))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/131")) func commandLineFollowsTheLoadExtensionOrder() {
        let p = ExtensionProfiles(folders: ["b": ["Profile 2", "Default"]])
        #expect(p.commandLineValue(forFolders: ["a", "b", "c"]) == "*,Default|Profile 2,*")
        #expect(p.commandLineValue(forFolders: ["a", "c"]) == nil, "no switch when every folder loads everywhere")
        #expect(ExtensionProfiles(folders: ["a": []]).commandLineValue(forFolders: ["a"]) == "", "an empty list loads nowhere")
    }

    @Test func savedAsAPlainObject() throws {
        let p = ExtensionProfiles(folders: ["a": ["Default"]])
        #expect(String(decoding: try JSONEncoder().encode(p), as: UTF8.self) == #"{"a":["Default"]}"#)
        #expect(try JSONDecoder().decode(ExtensionProfiles.self, from: Data("{}".utf8)) == ExtensionProfiles())
    }
}
