import Testing
@testable import CommandREPL

@Suite("Tokenizer")
struct TokenizerTests {

    @Test("splits on whitespace")
    func plainWords() {
        let tokens = Tokenizer.tokens(in: "build target --flavor vanilla")
        #expect(tokens.map(\.text) == ["build", "target", "--flavor", "vanilla"])
        #expect(tokens[0].start == 0)
        #expect(tokens[0].end == 5)
    }

    @Test("collapses runs of whitespace")
    func extraWhitespace() {
        let tokens = Tokenizer.tokens(in: "  build   target  ")
        #expect(tokens.map(\.text) == ["build", "target"])
        #expect(tokens[0].start == 2)
    }

    @Test("keeps double-quoted spans intact")
    func doubleQuotes() {
        let tokens = Tokenizer.tokens(in: #"build "my target" --flavor vanilla"#)
        #expect(tokens.map(\.text) == ["build", "my target", "--flavor", "vanilla"])
        #expect(tokens[1].isQuoted)
    }

    @Test("keeps single-quoted spans literal")
    func singleQuotes() {
        let tokens = Tokenizer.tokens(in: #"build 'a \n b'"#)
        #expect(tokens.map(\.text) == ["build", #"a \n b"#])
    }

    @Test("honors escapes inside and outside double quotes")
    func escapes() {
        #expect(Tokenizer.tokens(in: #"a\ b"#).map(\.text) == ["a b"])
        #expect(Tokenizer.tokens(in: #""say \"hi\"""#).map(\.text) == [#"say "hi""#])
    }

    @Test("runs an unterminated quote to end of line")
    func unterminatedQuote() {
        // The user is mid-typing whenever completion runs, so this must not fail.
        let tokens = Tokenizer.tokens(in: #"build "my tar"#)
        #expect(tokens.map(\.text) == ["build", "my tar"])
    }

    @Test("a path with spaces survives round-tripping")
    func pathWithSpaces() {
        let quoted = Tokenizer.quoteIfNeeded("/Users/me/My Projects/tron.json")
        let tokens = Tokenizer.tokens(in: "build --config \(quoted)")
        #expect(tokens.map(\.text) == ["build", "--config", "/Users/me/My Projects/tron.json"])
    }

    @Test("quoting is skipped when unnecessary")
    func noNeedlessQuoting() {
        #expect(Tokenizer.quoteIfNeeded("plain.json") == "plain.json")
    }

    // MARK: split(_:cursor:)

    @Test("cursor after a word treats it as the partial token")
    func cursorAtWordEnd() {
        let (completed, partial) = Tokenizer.split("build tar", cursor: 9)
        #expect(completed.map(\.text) == ["build"])
        #expect(partial?.text == "tar")
        #expect(partial?.start == 6)
    }

    @Test("cursor after whitespace starts a new token")
    func cursorAfterSpace() {
        let (completed, partial) = Tokenizer.split("build ", cursor: 6)
        #expect(completed.map(\.text) == ["build"])
        #expect(partial == nil)
    }

    @Test("cursor mid-word truncates at the cursor")
    func cursorMidWord() {
        // "build tar|get" -- completion should see "tar", not "target".
        let (completed, partial) = Tokenizer.split("build target", cursor: 9)
        #expect(completed.map(\.text) == ["build"])
        #expect(partial?.text == "tar")
    }

    @Test("cursor at position zero yields nothing")
    func cursorAtStart() {
        let (completed, partial) = Tokenizer.split("build", cursor: 0)
        #expect(completed.isEmpty)
        #expect(partial == nil)
    }

    @Test("cursor inside a quoted token keeps the quoted text")
    func cursorInQuotedToken() {
        let (_, partial) = Tokenizer.split(#"build --config "my fi"#, cursor: 22)
        #expect(partial?.text == "my fi")
    }
}
