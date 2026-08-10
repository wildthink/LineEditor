import Testing
@testable import CommandREPL
@testable import LineEditor

/// Covers the bridge between a ``CompletionProvider`` and bestline's C callback.
///
/// bestline replaces the *entire* line with whatever a completion returns
/// (`memcpy(ls->buf, cvec[i], n + 1)`) and moves the cursor by the length delta,
/// so the bridge must splice the candidate into `head + candidate + tail`. An
/// error here silently mangles the user's input, and it cannot be caught by
/// provider-level tests.
@Suite("CompletionBridge")
struct CompletionBridgeTests {

    /// Returns fixed candidates for whatever token the cursor is on.
    struct StubProvider: CompletionProvider {
        var replacingFrom: Int
        var values: [String]

        func complete(_ request: CompletionRequest) -> CompletionResult {
            CompletionResult(replacingFrom: replacingFrom, candidates: values.map { Completion($0) })
        }
    }

    @Test("splices a candidate over the token, preserving the head")
    func splicesOverToken() {
        let line = "build --fl"
        let lines = CompletionBridge.replacementLines(
            for: line,
            byteCursor: line.utf8.count,
            provider: StubProvider(replacingFrom: 6, values: ["--flavor"]))
        #expect(lines == ["build --flavor"])
    }

    @Test("preserves text after the cursor")
    func preservesTail() {
        // "build --fl|avor extra" -- completing mid-line must keep the tail.
        let line = "build --fl extra"
        let lines = CompletionBridge.replacementLines(
            for: line,
            byteCursor: 10,
            provider: StubProvider(replacingFrom: 6, values: ["--flavor"]))
        #expect(lines == ["build --flavor extra"])
    }

    @Test("inserts at the cursor when the token is empty")
    func insertsAtCursor() {
        let line = "build "
        let lines = CompletionBridge.replacementLines(
            for: line,
            byteCursor: line.utf8.count,
            provider: StubProvider(replacingFrom: 6, values: ["target"]))
        #expect(lines == ["build target"])
    }

    @Test("returns one full line per candidate")
    func multipleCandidates() {
        let line = "b"
        let lines = CompletionBridge.replacementLines(
            for: line,
            byteCursor: 1,
            provider: StubProvider(replacingFrom: 0, values: ["build", "bundle"]))
        #expect(lines == ["build", "bundle"])
    }

    @Test("no candidates yields no replacements")
    func noCandidates() {
        let lines = CompletionBridge.replacementLines(
            for: "build ",
            byteCursor: 6,
            provider: StubProvider(replacingFrom: 6, values: []))
        #expect(lines.isEmpty)
    }

    @Test("clamps a replacement span that runs past the cursor")
    func clampsOutOfRangeSpan() {
        // A misbehaving provider must not be able to crash the editor.
        let line = "build"
        let lines = CompletionBridge.replacementLines(
            for: line,
            byteCursor: 5,
            provider: StubProvider(replacingFrom: 99, values: ["x"]))
        #expect(lines == ["buildx"])
    }

    // MARK: Byte vs. character offsets

    @Test("converts a multi-byte cursor offset to a character offset")
    func multiByteCursor() {
        // "café " is 6 UTF-8 bytes but 5 Characters; bestline reports bytes.
        let line = "café bu"
        #expect(line.utf8.count == 8)
        #expect(line.count == 7)

        let lines = CompletionBridge.replacementLines(
            for: line,
            byteCursor: line.utf8.count,
            provider: StubProvider(replacingFrom: 5, values: ["build"]))
        #expect(lines == ["café build"])
    }

    @Test("maps byte offsets to character offsets across a grapheme cluster")
    func characterOffsetConversion() {
        let line = "café x"
        #expect(CompletionBridge.characterOffset(in: line, forByteOffset: 0) == 0)
        // 5 bytes in is just past "café" (4 chars).
        #expect(CompletionBridge.characterOffset(in: line, forByteOffset: 5) == 4)
        #expect(CompletionBridge.characterOffset(in: line, forByteOffset: line.utf8.count)
            == line.count)
    }

    @Test("an offset past the end clamps to the end")
    func offsetPastEnd() {
        let line = "abc"
        #expect(CompletionBridge.characterOffset(in: line, forByteOffset: 99) == 3)
    }
}
