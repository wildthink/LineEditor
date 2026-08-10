/// A demo REPL exercising the interactive features of `CommandREPL`.
///
/// Run it with `swift run repl`, then try:
///
/// ```
/// gre<Tab>                 # subcommand completion
/// greet --sty<Tab>         # option-name completion
/// greet --style <Tab>      # enum-value completion, with descriptions
/// report --input <Tab>     # file completion, filtered to .json
/// report --output <Tab>    # directory completion
/// .form greet              # guided form
/// ```
import ArgumentParser
import CommandREPL
import Foundation
import LineEditor

struct Demo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "demo",
        abstract: "Demonstrates an interactive shell for ArgumentParser commands.",
        version: "2.0.0",
        subcommands: [Greet.self, Report.self, Shell.self]
    )
}

/// A separate entry point, because `AsyncParsableCommand` supplies its own
/// `static func main()` and would win over an override declared on `Demo`.
@main
struct DemoMain {
    static func main() async throws {
        try await Demo.readEvalPrintLoop()
    }
}

/// Exercises enum values, repeating options, flags, and a required positional.
struct Greet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "greet",
        abstract: "Greet someone, loudly or otherwise."
    )

    enum Style: String, CaseIterable, ExpressibleByArgument {
        case plain, excited, formal
    }

    @Argument(help: "Who to greet.")
    var name: String

    @Option(name: [.short, .long], help: "How to phrase the greeting.")
    var style: Style = .plain

    @Option(name: .long, parsing: .singleValue, help: "Extra recipients. Repeatable.")
    var also: [String] = []

    @Flag(name: [.short, .long], help: "Shout it.")
    var loud: Bool = false

    func run() async throws {
        var names = [name] + also
        let greeting: String
        switch style {
        case .plain: greeting = "Hello"
        case .excited: greeting = "Hey there"
        case .formal: greeting = "Good day"
        }
        names = names.map { "\(greeting), \($0)" }
        let text = names.joined(separator: "\n")
        print(loud ? text.uppercased() : text)
    }
}

/// Exercises file and directory completion.
struct Report: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Summarize a JSON file."
    )

    @Option(name: [.short, .long], help: "JSON file to read.", completion: .file(extensions: ["json"]))
    var input: String

    @Option(name: [.short, .long], help: "Directory to write into.", completion: .directory)
    var output: String?

    func run() async throws {
        print("Would read \(input), writing to \(output ?? "stdout")")
    }
}

/// Exercises `.shellCommand` and `.custom` completion sources.
struct Shell: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shell",
        abstract: "Look something up from the environment."
    )

    @Option(name: .long, help: "A user on this machine.", completion: .shellCommand("ls /Users"))
    var user: String?

    @Option(name: .long, help: "An environment variable.", completion: .custom { _, _, _ in
        ProcessInfo.processInfo.environment.keys.sorted()
    })
    var variable: String?

    func run() async throws {
        if let user { print("user: \(user)") }
        if let variable {
            print("\(variable) = \(ProcessInfo.processInfo.environment[variable] ?? "<unset>")")
        }
    }
}
