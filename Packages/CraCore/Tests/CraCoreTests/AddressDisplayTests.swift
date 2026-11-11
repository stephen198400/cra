import CraCore
import Testing

/// The toolbar address while it isn't edited: host, then " / title" (Dia).
struct AddressDisplayTests {
    @Test func hostThenTitle() {
        let p = AddressDisplay.parts(host: "sanjoseca.gov", title: "Building Division City of San José")
        #expect(p == .init(host: "sanjoseca.gov", detail: " / Building Division City of San José"))
    }

    @Test func aTitleThatIsTheAddressIsLeftOut() {
        #expect(AddressDisplay.parts(host: "example.com", title: "").detail.isEmpty)
        #expect(AddressDisplay.parts(host: "example.com", title: "   ").detail.isEmpty)
        #expect(AddressDisplay.parts(host: "example.com", title: "https://www.example.com/").detail.isEmpty)
        #expect(AddressDisplay.parts(host: "example.com", title: "Example.com").detail.isEmpty)
        #expect(AddressDisplay.parts(host: "example.com", title: "example.com/docs").detail == " / example.com/docs")
    }

    @Test func titleWhitespaceFolds() {
        #expect(AddressDisplay.parts(host: "a.org", title: " Line one\n  two\t").detail == " / Line one two")
    }

    /// Show Full URL (#88's option): the dim path after the host, no title.
    @Test func fullURLShowsThePathInstead() {
        #expect(AddressDisplay.parts(host: "a.org", title: "Docs", path: "/docs/1") == .init(host: "a.org", detail: "/docs/1"))
    }
}
