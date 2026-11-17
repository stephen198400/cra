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

struct DiaThemeTests {
    /// Dia's sidebar, measured from its screenshots (17 Nov): near-white over the blurred desktop
    /// while macOS is light, an opaque blue-black while it is dark, both without grain.
    @Test func diaFollowsMacOSWithItsTwoGreys() throws {
        let dia = SpaceTheme.dia
        #expect(dia.followsSystem)
        let light = dia.resolved(systemDark: false), dark = dia.resolved(systemDark: true)
        #expect(light.colors == ["#F7F7F7", "#F7F7F7"] && !light.isDark && light.vibrant && light.intensity == 0.53)
        #expect(dark.colors == ["#22262D", "#262B31"] && dark.isDark && !dark.vibrant && dark.intensity == 1)
        for half in [light, dark] { #expect(!half.solid && half.noise == 0) }
        #expect(try JSONDecoder().decode(SpaceTheme.self, from: JSONEncoder().encode(dia)) == dia)
    }
}
