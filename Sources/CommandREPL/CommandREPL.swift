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

public struct CommandREPLRunner<Cmd: ParsableCommand> {
    public typealias Command = Cmd
    public let cmd: Cmd.Type
    /// Returns the path to the persistent history file in the user's home directory.
    public var historyPath: String
    
    public init(cmd: Cmd.Type, historyPath: String? = nil) {
        self.cmd = cmd
        if let historyPath {
            self.historyPath = historyPath
        } else {
            let home = ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
            self.historyPath = "\(home)/.\(cmd._commandName)_history"
        }
    }

    /// Starts the interactive REPL session.
    ///
    /// The loop continues until the user types `exit` or sends EOF (Ctrl-D).
    @MainActor public func run() throws {
        
        var editor = LineEditor()
                
        // Load history file (ignore errors if missing)
        try? editor.loadHistory(at: historyPath)
        
        /// Configure a small set of completion candidates for demonstration.
        let cmds = cmd.configuration.subcommands
        var cmd_names: [String] = []
        
        for cmd in cmds {
            cmd_names.append(cmd._commandName)
        }
        cmd_names.append(".exit")
        cmd_names.append(".repl")
        cmd_names.append(".ding")
        editor.setCompletions(cmd_names)
                
        /// Read, evaluate, and print loop.
        ///
        /// - Adds non-empty inputs to history
        /// - Exits on `exit`
         while let line = editor.readLine(prompt: "\(cmd._commandName)> ")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        {
            if !line.isEmpty { editor.addHistory(line) }
            if line == ".exit" { break }
            let words = line.split(separator: " ")
            
            if line.hasPrefix(".ding") {
                editor.ding()
                continue
            }
            if line.hasPrefix(".repl"), words.count > 1, let subc = words.last {
                let cmd = cmd.configuration.subcommands.first(where: {
                    $0._commandName == String(subc)
                })
                try cmd?.readEvalPrintLoop()
            }
            do {
                try cmd.evaluate(argv: words)
            } catch {
                cmd.report(error: error)
            }
        }
        print("")
        
        /// Persist history on exit (errors are reported to stderr but do not abort).
        do { try editor.saveHistory(to: historyPath) } catch {
            fputs("Warning: \(error)\n", stderr)
        }
    }
}

public extension CommandREPLRunner {
    @MainActor
    static func main() throws {
        
        if CommandLine.arguments.contains("-i")
            || CommandLine.arguments.contains("-repl")
        {
            try Self(cmd: Command.self).run()
        } else {
            Cmd.evaluateAsRoot(
                argv: CommandLine.arguments.dropFirst())
        }
    }
}

public extension ParsableCommand {
    @MainActor
    static func readEvalPrintLoop() throws {
        try CommandREPLRunner(cmd: self).run()
    }
}
#endif
