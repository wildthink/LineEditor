import ArgumentParser
import Foundation
import LineEditor
import Testing
@testable import CommandREPL

@Suite("Completion", .serialized)
@MainActor
struct CompletionTests {

    // MARK: 1-2. Subcommand position

    @Test("offers subcommands on an empty line")
    func subcommandsOnEmptyLine() throws {
        let model = try CommandModel.fixture()
        #expect(completions("", model: model).sorted() == ["build", "help", "nested"])
    }

    @Test("filters subcommands by prefix")
    func subcommandPrefix() throws {
        let model = try CommandModel.fixture()
        #expect(completions("bu", model: model) == ["build"])
    }

    @Test("offers meta-commands alongside subcommands")
    func metaCommands() throws {
        let model = try CommandModel.fixture()
        let result = completions(".", model: model, metaCommands: [".exit", ".form"])
        #expect(result.sorted() == [".exit", ".form"])
    }

    @Test("descends into nested subcommands")
    func nestedSubcommands() throws {
        let model = try CommandModel.fixture()
        #expect(completions("nested ", model: model).contains("leaf"))
    }

    // MARK: 3. Option values

    @Test("completes enum cases after an option expecting one")
    func enumValues() throws {
        let model = try CommandModel.fixture()
        #expect(completions("build --flavor ", model: model)
            == ["vanilla", "chocolate", "strawberry"])
    }

    @Test("filters enum cases by prefix")
    func enumValuePrefix() throws {
        let model = try CommandModel.fixture()
        #expect(completions("build --flavor ch", model: model) == ["chocolate"])
    }

    @Test("completes enum cases after a short option name")
    func enumValuesViaShortName() throws {
        let model = try CommandModel.fixture()
        #expect(completions("build -f ", model: model).contains("strawberry"))
    }

    @Test("runs a .custom closure in-process")
    func customCompletion() throws {
        // Proves the ---completion re-entry: the closure lives in the command,
        // is invoked through the parser, and never leaves the process.
        let model = try CommandModel.fixture()
        #expect(completions("build --pick ", model: model) == ["alpha", "beta", "gamma"])
    }

    @Test("filters .custom results by prefix")
    func customCompletionPrefix() throws {
        let model = try CommandModel.fixture()
        #expect(completions("build --pick be", model: model) == ["beta"])
    }

    // MARK: 4. Option names

    @Test("offers option names after a dash")
    func optionNames() throws {
        let model = try CommandModel.fixture()
        let result = completions("build -", model: model)
        #expect(result.contains("--flavor"))
        #expect(result.contains("--verbose"))
        #expect(result.contains("--config"))
    }

    @Test("filters option names by prefix")
    func optionNamePrefix() throws {
        let model = try CommandModel.fixture()
        #expect(completions("build --fl", model: model) == ["--flavor"])
    }

    @Test("does not re-offer a non-repeating option already used")
    func suppressesUsedOptions() throws {
        let model = try CommandModel.fixture()
        let result = completions("build --flavor vanilla --", model: model)
        #expect(!result.contains("--flavor"))
    }

    @Test("keeps offering a repeating option")
    func repeatingOptionStaysAvailable() throws {
        let model = try CommandModel.fixture()
        let result = completions("build --tag one --", model: model)
        #expect(result.contains("--tag"))
    }

    // MARK: 5. Positionals

    @Test("does not offer subcommand names in positional position")
    func positionalsAreNotSubcommands() throws {
        let model = try CommandModel.fixture()
        // `build` has no completion source for <target>, so nothing is offered --
        // importantly, it does not fall back to offering sibling subcommands.
        #expect(completions("build ", model: model).isEmpty)
    }

    @Test("stops offering values past the last positional")
    func exhaustedPositionals() throws {
        let model = try CommandModel.fixture()
        #expect(completions("build one two three ", model: model).isEmpty)
    }

    // MARK: File and directory sources

    @Test("completes files filtered by extension")
    func fileCompletion() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try directory.write("manifest.json")
        try directory.write("notes.txt")
        try directory.makeSubdirectory("subdir")

        let model = try CommandModel.fixture()
        let result = completions("build --config \(directory.path)/", model: model)

        #expect(result.contains { $0.hasSuffix("manifest.json") })
        #expect(!result.contains { $0.hasSuffix("notes.txt") })
        // Directories are always offered so the user can descend into them.
        #expect(result.contains { $0.hasSuffix("subdir/") })
    }

    @Test("completes directories only")
    func directoryCompletion() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try directory.write("manifest.json")
        try directory.makeSubdirectory("subdir")

        let model = try CommandModel.fixture()
        let result = completions("build --output-dir \(directory.path)/", model: model)

        #expect(result.contains { $0.hasSuffix("subdir/") })
        #expect(!result.contains { $0.hasSuffix("manifest.json") })
    }

    @Test("quotes a path containing spaces")
    func quotesPathsWithSpaces() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try directory.write("my manifest.json")

        let model = try CommandModel.fixture()
        let result = completions("build --config \(directory.path)/", model: model)
        #expect(result.contains { $0.hasSuffix(#"my manifest.json""#) })
    }

    // MARK: Replacement span

    @Test("replaces only the token under the cursor")
    func replacementSpan() throws {
        let model = try CommandModel.fixture()
        let provider = CommandCompletionProvider(root: Root.self, model: model)
        let line = "build --flavor ch"
        let result = provider.complete(CompletionRequest(line: line, cursor: line.count))
        // "ch" begins at offset 15; everything before it must survive the splice.
        #expect(result.replacingFrom == 15)
    }

    @Test("replacement starts at the cursor when it follows whitespace")
    func replacementSpanAfterSpace() throws {
        let model = try CommandModel.fixture()
        let provider = CommandCompletionProvider(root: Root.self, model: model)
        let line = "build --flavor "
        let result = provider.complete(CompletionRequest(line: line, cursor: line.count))
        #expect(result.replacingFrom == line.count)
    }

    // MARK: Hints

    @Test("hints the next subcommand at the root")
    func hintsSubcommand() throws {
        let model = try CommandModel.fixture()
        let provider = CommandCompletionProvider(root: Root.self, model: model)
        #expect(provider.hint(for: "") == " <subcommand>")
    }

    @Test("hints a required positional")
    func hintsRequiredPositional() throws {
        let model = try CommandModel.fixture()
        let provider = CommandCompletionProvider(root: Root.self, model: model)
        #expect(provider.hint(for: "build ") == " <target> (required)")
    }

    @Test("hints an option's value placeholder")
    func hintsOptionValue() throws {
        let model = try CommandModel.fixture()
        let provider = CommandCompletionProvider(root: Root.self, model: model)
        #expect(provider.hint(for: "build --config ") == " <config>")
    }

    @Test("does not hint mid-word")
    func noHintMidWord() throws {
        let model = try CommandModel.fixture()
        let provider = CommandCompletionProvider(root: Root.self, model: model)
        #expect(provider.hint(for: "buil") == nil)
    }
}

// MARK: - Temporary directory helper

/// A scratch directory, removed by an explicit ``remove()`` call.
///
/// Deliberately not a class with a `deinit`: ARC may release such an object
/// immediately after its last use, which here would be reading `.path` to build
/// the completion line -- deleting the directory before completion ever runs.
struct TemporaryDirectory {
    let url: URL
    var path: String { url.path }

    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CommandREPLTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ name: String, contents: String = "{}") throws {
        try contents.write(
            to: url.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func makeSubdirectory(_ name: String) throws {
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent(name), withIntermediateDirectories: true)
    }
}
