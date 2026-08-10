import ArgumentParser
import Foundation
import LineEditor
@testable import CommandREPL

// MARK: - Command fixture

/// A command tree exercising every argument shape the completion engine
/// understands: nested subcommands, aliases, enum values, repeating options,
/// file and directory completion, and a `.custom` closure.
struct Root: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "root",
        abstract: "Test fixture.",
        subcommands: [Build.self, Nested.self]
    )
}

enum Flavor: String, CaseIterable, ExpressibleByArgument {
    case vanilla, chocolate, strawberry
}

struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build a thing.",
        aliases: ["b"]
    )

    @Argument(help: "The target to build.")
    var target: String

    @Argument(help: "An optional second target.")
    var extra: String?

    @Option(name: [.short, .long], help: "Which flavor.")
    var flavor: Flavor = .vanilla

    @Option(name: .long, parsing: .singleValue, help: "Tags. Repeatable.")
    var tag: [String] = []

    @Option(name: [.short, .long], help: "Config file.", completion: .file(extensions: ["json"]))
    var config: String?

    @Option(name: .long, help: "Output dir.", completion: .directory)
    var outputDir: String?

    @Option(name: .long, help: "A computed value.", completion: .custom { _, _, _ in
        ["alpha", "beta", "gamma"]
    })
    var pick: String?

    @Flag(name: [.short, .long], help: "Be verbose.")
    var verbose: Bool = false

    func run() throws {}
}

struct Nested: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nested",
        abstract: "Has children.",
        subcommands: [Leaf.self]
    )
}

struct Leaf: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "leaf", abstract: "A leaf.")
    @Option(name: .long, help: "A leaf option.") var value: String?
    func run() throws {}
}

// MARK: - Test helpers

extension CommandModel {
    static func fixture() throws -> CommandModel { try CommandModel(Root.self) }
}

/// Runs a completion query against the fixture and returns the candidate values.
///
/// The cursor defaults to end-of-line, which is where completion is requested
/// in practice.
@MainActor
func completions(
    _ line: String,
    cursor: Int? = nil,
    model: CommandModel,
    metaCommands: [String] = []
) -> [String] {
    let provider = CommandCompletionProvider(
        root: Root.self, model: model, metaCommands: metaCommands)
    let result = provider.complete(
        CompletionRequest(line: line, cursor: cursor ?? line.count))
    return result.candidates.map(\.value)
}

/// A ``FormInput`` that replays a fixed script, for driving forms without a terminal.
final class ScriptedInput: FormInput {
    private var answers: [String]
    private(set) var prompts: [String] = []

    init(_ answers: [String]) {
        self.answers = answers
    }

    func readLine(prompt: String) -> String? {
        prompts.append(prompt)
        guard !answers.isEmpty else { return nil }  // EOF
        return answers.removeFirst()
    }

    func setCompletionProvider(_ provider: any CompletionProvider) {}
}
