//
//  CommandREPL.swift
//  LineEditor
//
//  Created by Jason Jobe on 11/19/25.
//

#if canImport(ArgumentParser)
import ArgumentParser
import Foundation
import LineEditor

/// The REPL Tool Protocol
///
/// This type configures and runs an interactive loop backed by `LineEditor`.
/// It loads and saves history, configures completion candidates, and routes
/// lines beginning with ParsableCommand._commandName to ParsableCommand
/// type using the an instantiation of`CommandREPL<Cmd>`.
@MainActor
public protocol CommandREPL<Cmd> {
    associatedtype Cmd: ParsableCommand
    static func main() throws
    static func run() throws
}

public extension CommandREPL {
     static func main() throws {
        
        if CommandLine.arguments.contains("-i")
        || CommandLine.arguments.contains("-repl")
        {
            try run()
        } else {
            Cmd.evaluateAsRoot(argv: CommandLine.arguments)
        }
    }
    
    /// Starts the interactive REPL session.
    ///
    /// The loop continues until the user types `exit` or sends EOF (Ctrl-D).
    @MainActor static func run() throws {

        var editor = LineEditor()
        
        /// Returns the path to the persistent history file in the user's home directory.
        func historyPath() -> String {
            let home = ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
            return "\(home)/.\(Cmd._commandName)_history"
        }
        
        // Load history file (ignore errors if missing)
        try? editor.loadHistory(at: historyPath())
        
        /// Configure a small set of completion candidates for demonstration.
        let cmds = Cmd.configuration.subcommands
        var cmd_names: [String] = []
        
        for cmd in cmds {
            cmd_names.append(cmd._commandName)
        }
        cmd_names.append("exit")
        editor.setCompletions(cmd_names)
        
        print("Read-eval-loop for", Cmd._commandName,
              "\nTab for completion, Ctrl-D to quit.")
        
        /// Read, evaluate, and print loop.
        ///
        /// - Adds non-empty inputs to history
        /// - Exits on `exit`
        /// - If input begins with `cmd`, forwards the remainder to `HelloWorld`
        /// - Otherwise echoes the input
        while let line = editor.readLine(prompt: "\(Cmd._commandName)> ")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        {
            if !line.isEmpty { editor.addHistory(line) }
            if line == "exit" { break }
            let words = line.split(separator: " ")
            do {
                try Cmd.evaluate(argv: words)
            } catch {
                Cmd.report(error: error)
            }
        }
        print("")
        
        /// Persist history on exit (errors are reported to stderr but do not abort).
        do { try editor.saveHistory(to: historyPath()) } catch {
            fputs("Warning: \(error)\n", stderr)
        }
    }
}
#endif
