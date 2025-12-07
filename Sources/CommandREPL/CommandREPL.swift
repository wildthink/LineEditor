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
    
    func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout.stride(ofValue: info)
        
        let sysctlResult = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        
        guard sysctlResult == 0 else {
            assertionFailure("sysctl failed")
            return false
        }
        
        return (info.kp_proc.p_flag & P_TRACED) != 0
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

    /// Starts the interactive REPL session.
    ///
    /// The loop continues until the user types `exit` or sends EOF (Ctrl-D).
    @MainActor public func run() throws {
        
        var editor = LineEditor(historyFile: historyPath)

        /// Configure a small set of completion candidates for demonstration.
        let cmds = cmd.configuration.subcommands
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
