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

public protocol InteractiveCommand {
    var commandName: String { get }
    func evaluate(input line: String) throws
    var interactive: Bool { get }
}

/// The REPL Tool Protocol
///
/// This type configures and runs an interactive loop backed by `LineEditor`.
/// It loads and saves history, configures completion candidates, and routes
/// lines beginning with ParsableCommand._commandName to ParsableCommand
/// type using the an instantiation of`CommandREPL<Cmd>`.
@MainActor
public struct CommandREPLRunner {
    public let cmd: any ParsableCommand.Type
    public var historyPath: String

    public init<C: ParsableCommand>(
        cmd: C.Type,
        historyPath: String? = nil
    ) {

        self.cmd = cmd
        if let historyPath {
            self.historyPath = historyPath
        } else {
            /// Returns the path to the persistent history file in the user's home directory.
            let home = ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
            self.historyPath = "\(home)/.\(cmd.commandName)_history"
        }
    }
        
    public func handle(input line: String) throws {
        if line == ".exit" { return }
        let words = line.split(separator: " ")
        
        if line.hasPrefix(".repl"), words.count > 1, let subc = words.last {
            let cmd = cmd.configuration.subcommands.first(where: {
                $0._commandName == String(subc)
            })
            try cmd?.readEvalPrintLoop()
        }
        try cmd.evaluate(argv: words)
    }

    func subcmd<S: StringProtocol>(for argv: [S]) -> (Int, (any ParsableCommand.Type)?) {
        var pc: ParsableCommand.Type? = cmd
        var next: ParsableCommand.Type? = cmd

        var count = 0
        for sub_cmd in argv {
            next = next?.configuration.subcommands
                .first { $0._commandName == sub_cmd }
            if let next {
                pc = next
                count += 1
            }
        }
        return (count, pc)
    }
    
    @MainActor public func run() throws {
        let argv: [String] = CommandLine.arguments
        let args = Array(argv.dropFirst())
        let (ndx, subc) = subcmd(for: args)
        let root = subc ?? cmd
        let rargv = Array(args.dropFirst(ndx))
        do {
            var next = try root.parseAsRoot(rargv)
            if let icmd = next as? InteractiveCommand,
               icmd.interactive {
                try repl(icmd: next)
            } else {
                try next.run()
            }
        } catch {
            root.report(error: error)
        }
    }
    
    /// Starts the interactive REPL session.
    ///
    /// The loop continues until the user types `exit` or sends EOF (Ctrl-D).
    @MainActor public func repl<C: ParsableCommand>(icmd: C) throws {
        
        var editor = LineEditor(historyFile: historyPath)

        /// Configure a small set of completion candidates for demonstration.
        let cmds = C.configuration.subcommands
        var cmd_names: [String] = []
        
        for cmd in cmds {
            cmd_names.append(cmd._commandName)
        }
        cmd_names.append(".exit")
        cmd_names.append(".repl")

        editor.setCompletions(cmd_names)

        /// Read, evaluate, and print loop.
        ///
        /// - Adds non-empty inputs to history
        /// - Exits on `exit`
        editor.readEvaluateLoop(prompt: "\(cmd._commandName) > ") { line in
            if line == ".exit" { return .exit }
             do {
                 try handle(input: line)
             } catch {
                 cmd.report(error: error)
             }
            return .step
        }
    }
}


public extension ParsableCommand {
    
    static var commandName: String { _commandName }
    
    @MainActor
    static func readEvalPrintLoop() throws {
        try CommandREPLRunner(cmd: self).run()
    }
}
#endif

