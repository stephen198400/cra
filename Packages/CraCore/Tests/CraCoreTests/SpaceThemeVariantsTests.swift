import Foundation
import Testing
@testable import CraCore

struct SpaceThemeVariantsTests {
    /// The theme editor's Auto keeps a colour of its own for each side: green while macOS is
    /// light, blue while it is dark, instead of both halves coming from one colour.
    @Test func autoKeepsALightAndADarkColour() throws {
        let green = ["#6CF054"], blue = ["#5466F0"]
        let t = SpaceThemeVariants.theme(key: green, darkKey: blue, intensity: 0.8, noise: 0.1, appearance: "auto")
        #expect(t.key == green)
        #expect(t.dark?.key == blue)
        let light = t.resolved(systemDark: false), dark = t.resolved(systemDark: true)
        #expect(light.colors == SpaceThemeVariants.light(key: green, intensity: 0.8, noise: 0.1).colors)
        #expect(dark.colors == SpaceThemeVariants.dark(key: blue, intensity: 0.8, noise: 0.1).colors)
        // The dark side's colour survives sidebar.json.
        let back = try JSONDecoder().decode(SpaceTheme.self, from: JSONEncoder().encode(t))
        #expect(back.dark?.key == blue)
        #expect(back == t)
    }

    /// Light and Dark keep one side: Dark is built from the dark colour, Light from the light one.
    @Test func lightAndDarkUseTheirOwnColour() {
        let green = ["#6CF054"], blue = ["#5466F0"]
        let dark = SpaceThemeVariants.theme(key: green, darkKey: blue, intensity: 0.8, noise: 0, appearance: "dark")
        #expect(dark.colors == SpaceThemeVariants.dark(key: blue, intensity: 0.8, noise: 0).colors)
        #expect(dark.key == blue)
        let light = SpaceThemeVariants.theme(key: green, darkKey: blue, intensity: 0.8, noise: 0, appearance: "light")
        #expect(light.key == green)
    }

    /// Without a dark colour (a theme saved before it existed) both halves come from the one key.
    @Test func noDarkColourUsesTheKeyForBoth() {
        let t = SpaceThemeVariants.theme(key: ["#6CF054"], intensity: 0.8, noise: 0, appearance: "auto")
        #expect(t.dark?.colors == SpaceThemeVariants.dark(key: ["#6CF054"], intensity: 0.8, noise: 0).colors)
        #expect(t.dark?.key == nil)
    }
}
