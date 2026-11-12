import CraCore
import Foundation
import Testing

/// Arc's tidy titles: per-site rules, always on.
struct TidyTitleRulesTests {
    let rules = TidyTitleRules.arc

    @Test func arcsRulesLoad() {
        #expect(rules.sites.count == 52)
        #expect(rules.site(forHost: "en.wikipedia.org")?.siteName == "Wikipedia")
    }

    @Test func titlesSeenInArc() {
        // Arc 1.171's sidebar, 4 Nov 2026.
        #expect(rules.tidy("Jupiter - Wikipedia", url: "https://en.wikipedia.org/wiki/Jupiter") == "Jupiter")
        #expect(rules.tidy("Y Combinator | Hacker News", url: "https://news.ycombinator.com/item?id=1") == "Y Combinator")
        // No rules for the BBC: the page's own title.
        #expect(rules.tidy("Climate - BBC News", url: "https://www.bbc.com/news/topics/x") == "Climate - BBC News")
    }

    @Test func pathAndFragmentRules() {
        #expect(rules.tidy("Wikipedia, the free encyclopedia", url: "https://en.wikipedia.org/wiki/Main_Page") == "Wikipedia")
        #expect(rules.tidy("Inbox (3) - me@example.com - Gmail", url: "https://mail.google.com/mail/u/0/#inbox") == "Gmail")
        #expect(rules.tidy("Starred - me@example.com - Gmail", url: "https://mail.google.com/mail/u/0/#starred") == "Starred")
        #expect(rules.tidy("Receipts - me@example.com - Gmail", url: "https://mail.google.com/mail/u/0/#label/Receipts") == "Receipts")
        #expect(rules.tidy("Amazon.com", url: "https://www.amazon.com/") == "Amazon")
    }

    @Test func removingPatternsAndHosts() {
        // removingPatterns: LinkedIn's counter and suffix both go.
        #expect(rules.tidy("(3) Jane Doe | LinkedIn", url: "https://www.linkedin.com/in/jane") == "Jane Doe")
        // www. is ignored, other subdomains aren't the site.
        #expect(rules.site(forHost: "WWW.Amazon.com") != nil)
        #expect(rules.site(forHost: "music.youtube.com") == nil)
        #expect(rules.tidy("x", url: "not a url") == "x")
        #expect(rules.tidy("", url: "https://en.wikipedia.org/wiki/X") == "")
    }

    @Test func aRuleLeavingNothingKeepsTheTitle() throws {
        let json = #"{"a.com": {"siteName": "A", "rules": [{"title": {"removingPattern": ".*"}}]}}"#
        let r = TidyTitleRules(sites: try JSONDecoder().decode([String: TidyTitleRules.Site].self, from: Data(json.utf8)))
        #expect(r.tidy("Anything", url: "https://a.com/") == "Anything")
    }
}
