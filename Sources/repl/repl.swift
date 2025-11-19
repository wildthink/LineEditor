/// An interactive REPL example using LineEditor and ArgumentParser.
///
/// This example demonstrates how to build a simple interactive shell that:
/// - Maintains input history across launches
/// - Provides tab-completion suggestions
/// - Echoes input by default
/// - Dispatches `cmd ...` lines to an `ArgumentParser`-based command
///
/// The `HelloWorld` command is used to show how to parse and execute commands
/// entered at the prompt using the `CommandREPL` helpers.
import Foundation
import ArgumentParser
import LineEditor
import CommandREPL

/// A minimal command used by the REPL to demonstrate command execution.
///
/// Run this command inside the REPL by typing, for example:
///
/// ```
/// cmd --name Alice
/// ```
///
/// The command prints a friendly greeting using the provided name.
struct HelloWorld: ParsableCommand {
    /// The command's metadata used by ArgumentParser.
    ///
    /// - `commandName`: The display name for help and usage.
    /// - `abstract`: A short description shown in help output.
    /// - `version`: The semantic version of the command.
    static let configuration = CommandConfiguration(
        commandName: "HelloWorld",
        abstract: "To demonstrate an interactive shell for executing commands",
        version: "0.1.0"
    )

    /// The name to greet.
    ///
    /// Provide with `--name <value>`. Defaults to `"World"` when omitted.
    @Option var name: String = "World"
    
    /// Executes the command, printing a greeting to standard output.
    func run() throws {
        print("Hello", name)
    }
}

/// The REPL entry point.
///
/// This type configures and runs an interactive loop backed by `LineEditor`.
/// It loads and saves history, configures completion candidates, and routes
/// lines beginning with `cmd` to the `HelloWorld` command using the
/// `CommandREPL` evaluation helpers.
@main
struct Repl: CommandREPL {
    typealias Cmd = HelloWorld
}

@MainActor
struct repl {
    /// Starts the interactive REPL session.
    ///
    /// The loop continues until the user types `exit` or sends EOF (Ctrl-D).
    static func main() {
        
        var editor = LineEditor()
        
        /// Returns the path to the persistent history file in the user's home directory.
        func historyPath() -> String {
            let home = ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
            return "\(home)/.editcli_history"
        }
        
        // Load history file (ignore errors if missing)
        do { try editor.loadHistory(at: historyPath()) } catch { /* no-op */ }
        
        /// Configure a small set of completion candidates for demonstration.
        editor.setCompletions([
            "help", "hello", "halt", "history", "host", "hover",
            "exit", "list", "load", "save"
        ])
        
        print("Libedit demo. Tab for completion, Ctrl-D to quit.")
        
        /// Read, evaluate, and print loop.
        ///
        /// - Adds non-empty inputs to history
        /// - Exits on `exit`
        /// - If input begins with `cmd`, forwards the remainder to `HelloWorld`
        /// - Otherwise echoes the input
        while let line = editor.readLine(prompt: "edit> ")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        {
            if !line.isEmpty { editor.addHistory(line) }
            if line == "exit" { break }
            let words = line.split(separator: " ")
            if words.first == "cmd" {
                /// Parse and run the `HelloWorld` command using CommandREPL helpers.
                do {
                    try HelloWorld.evaluate(argv: words.dropFirst())
                } catch {
                    HelloWorld.report(error: error)
                }
            } else {
                print("echo: \(line)")
            }
            
        }
        print("")
        
        /// Persist history on exit (errors are reported to stderr but do not abort).
        do { try editor.saveHistory(to: historyPath()) } catch {
            fputs("Warning: \(error)\n", stderr)
        }
    }
}
