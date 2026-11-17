import Foundation

/// The light and dark halves of an Auto theme (Arc: SpaceStyleEditorState+WindowTheme, which builds
/// `background.appearanceBased` from the editor's key colour).
public enum SpaceThemeVariants {
    /// What the theme editor makes of its pad: both halves for Auto, one for Light or Dark.
    /// Auto always gets both halves, one colour too (#155): Arc saves a swatch picked on Auto as one
    /// `single` theme that never changes with macOS, and copying that (0.1.30–0.1.32) left a space set
    /// to Auto stuck on one side. An imported Arc `single` stays on its side (ArcThemeImport, #171).
    /// `darkKey` is the pad's colours for the dark side (the editor keeps one set per side): Dark is
    /// built from it and Auto's dark half too; nil uses `key` for both, as before it existed.
    public static func theme(key: [String], darkKey: [String]? = nil, intensity: Double, noise: Double, appearance: String) -> SpaceTheme {
        let darkKey = darkKey ?? key
        var t: SpaceTheme
        switch appearance {
        case "light": t = half(light: true, key: key, intensity: intensity, noise: noise); t.key = key
        case "dark": t = half(light: false, key: darkKey, intensity: intensity, noise: noise); t.key = darkKey
        default:
            t = SpaceTheme(light: half(light: true, key: key, intensity: intensity, noise: noise),
                           dark: half(light: false, key: darkKey, intensity: intensity, noise: noise))
            t.key = key
            if darkKey != key { t.dark?.key = darkKey }
        }
        return t
    }

    /// One side from its pad colours; none is that side of Arc's colourless theme.
    private static func half(light isLight: Bool, key: [String], intensity: Double, noise: Double) -> SpaceTheme {
        if key.isEmpty { return colourless(intensity: intensity, noise: noise, appearance: isLight ? "light" : "dark") }
        return isLight ? light(key: key, intensity: intensity, noise: noise) : dark(key: key, intensity: intensity, noise: noise)
    }

    /// Arc's colourless theme, what its editor saves with no colour on the pad ("Tap to pick a color
    /// for this space", #300): the default space's two halves, base #C8CAFF / #FFE5E5 light and
    /// #01021F / #1A001F dark, as ArcThemeImport draws them (pinned against Arc's own file by
    /// `noColourIsArcsColourlessTheme`). Auto follows macOS; Light or Dark keeps that half. The
    /// intensity slider still sets the light half's.
    public static func colourless(intensity: Double, noise: Double, appearance: String) -> SpaceTheme {
        let light = SpaceTheme(colors: ["#CDCDFC", "#FFE5E5"], intensity: intensity, noise: noise, appearance: "light", accent: "#C8CAFF")
        let dark = SpaceTheme(colors: ["#2C273B", "#32263A"], intensity: 1, noise: noise, appearance: "dark", accent: "#010220")
        switch appearance {
        case "light": return light
        case "dark": return dark
        default: return SpaceTheme(light: light, dark: dark)
        }
    }

    /// The half shown while macOS is light, from the pad's colours: the colours themselves (Arc
    /// saves a colour picked in Light as that colour), lifted to Arc's default light half (HSL
    /// lightness 0.9, #8389FF → #C8CAFF) when they would read as a dark theme. One colour is Arc's
    /// one-dot theme (`blendedSingleColor`), a flat fill like an imported one (ArcThemeImport).
    public static func light(key: [String], intensity: Double, noise: Double) -> SpaceTheme {
        var t = SpaceTheme(colors: key, intensity: intensity, noise: noise, appearance: "auto", accent: key.first)
        if t.isDark { t.colors = key.map { shade($0, lightness: 0.9) }; t.accent = t.colors.first }
        t.appearance = "light"
        if t.colors.count == 1 { t.colors.append(t.colors[0]); t.solid = true }
        return t
    }

    /// The half shown while macOS is dark, from the pad's colours: Arc's default dark half keeps the
    /// key's hue at HSL lightness ≈ 0.064 (#8389FF → #01021F).
    public static func dark(key: [String], intensity: Double, noise: Double) -> SpaceTheme {
        let base = key.map { shade($0, lightness: 0.064) }
        // Drawn the way ArcThemeImport draws Arc's opaque dark halves: ~27% of the colour over #2B2632.
        let colors = base.map { hex in
            let k = HexColor.components(hex) ?? (0, 0, 0)
            func ch(_ v: Double, _ b: Double) -> Int { Int((v * 255 * 0.27 + b).rounded()) }
            return String(format: "#%02X%02X%02X", ch(k.r, 43), ch(k.g, 38), ch(k.b, 50))
        }
        // One colour stays one flat colour, without the gradient a lone stop gets (SpacePalette).
        return SpaceTheme(colors: colors.count == 1 ? colors + colors : colors, intensity: 1, noise: noise, appearance: "dark",
                          accent: base.first)
    }

    /// The colour's HSL hue and saturation at another lightness.
    static func shade(_ hex: String, lightness l: Double) -> String {
        let c = HexColor.components(hex) ?? (0.5, 0.5, 0.5)
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), d = mx - mn
        let l0 = (mx + mn) / 2
        let s = d == 0 ? 0 : d / (1 - abs(2 * l0 - 1))
        var h = 0.0
        if d > 0 {
            if mx == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == c.g { h = (c.b - c.r) / d + 2 }
            else { h = (c.r - c.g) / d + 4 }
            h = (h / 6 + 1).truncatingRemainder(dividingBy: 1)
        }
        let q = (1 - abs(2 * l - 1)) * min(1, s)
        let x = q * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1)), m = l - q / 2
        let (r, g, b): (Double, Double, Double)
        switch Int(h * 6) % 6 {
        case 0: (r, g, b) = (q, x, 0)
        case 1: (r, g, b) = (x, q, 0)
        case 2: (r, g, b) = (0, q, x)
        case 3: (r, g, b) = (0, x, q)
        case 4: (r, g, b) = (x, 0, q)
        default: (r, g, b) = (q, 0, x)
        }
        func byte(_ v: Double) -> Int { Int((max(0, min(1, v + m)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
