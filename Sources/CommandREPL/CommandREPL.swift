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

/// An interactive shell for any `ParsableCommand` tree.
///
/// Introspects the command with ``CommandModel`` and wires up:
///
/// - context-aware Tab completion (subcommands, option names, enum values,
///   file and directory paths, `.shellCommand` and `.custom` sources),
/// - inline hints showing what the line still expects,
/// - a guided ``CommandForm`` for filling a command out field by field,
/// - persistent history.
///
/// Commands are dispatched through the async `evaluate(argv:)`, so trees built
/// from `AsyncParsableCommand` run correctly.
@MainActor
public struct CommandREPLRunner<Root: ParsableCommand> {
    public let cmd: Root.Type
    public var historyPath: String
    let model: CommandModel

    /// Meta-commands handled by the REPL itself rather than the command tree.
    static var metaCommands: [String] { [".exit", ".help", ".form"] }

    public init(
        cmd: Root.Type,
        historyPath: String? = nil
    ) throws {
        self.cmd = cmd
        self.model = try CommandModel(cmd)
        if let historyPath {
            self.historyPath = historyPath
        } else {
            let home = ProcessInfo.processInfo.environment["HOME"]
                ?? FileManager.default.homeDirectoryForCurrentUser.path
            self.historyPath = "\(home)/.\(cmd._commandName)_history"
        }
    }

    /// Handles one line of input.
    ///
    /// - Returns: `.exit` when the REPL should stop.
    public func handle(input line: String, editor: LineEditor) async -> LineEditor.Action {
        let words = Tokenizer.tokens(in: line).map(\.text)
        guard let first = words.first else { return .step }

        switch first {
        case ".exit", ".quit":
            return .exit

        case ".help":
            print(cmd.helpMessage(for: CleanExit.helpRequest()))
            return .step

        case ".form":
            await runForm(path: Array(words.dropFirst()), editor: editor)
            return .step

        default:
            await cmd.evaluateAsRoot(argv: words)
            return .step
        }
    }

    /// Fills a command out interactively, then runs the argv it produces.
    private func runForm(path: [String], editor: LineEditor) async {
        let (command, consumed) = model.resolve(path: path)
        guard consumed.count == path.count else {
            print("Unknown command: \(path.joined(separator: " "))")
            return
        }
        guard command.visibleSubcommands.isEmpty else {
            let names = command.visibleSubcommands.map(\.commandName).joined(separator: ", ")
            print("`\(command.commandName)` has subcommands: \(names)")
            print("Use `.form \(path.joined(separator: " ")) <subcommand>`.")
            return
        }

        let form = CommandForm(root: cmd, model: model, path: consumed, command: command)
        guard let argv = form.run(editor: editor) else {
            print("Cancelled.")
            return
        }

        print("> \(argv.map(Tokenizer.quoteIfNeeded).joined(separator: " "))")
        await cmd.evaluateAsRoot(argv: argv)

        // Restore the line-level provider the form replaced.
        installCompletion(on: editor)
    }

    private func installCompletion(on editor: LineEditor) {
        editor.setCompletionProvider(
            CommandCompletionProvider(
                root: cmd,
                model: model,
                metaCommands: Self.metaCommands
            )
        )
    }

    /// Starts the interactive REPL session.
    ///
    /// The loop continues until the user types `.exit` or sends EOF (Ctrl-D).
    public func run() async throws {
        let editor = LineEditor(historyFile: historyPath)
        installCompletion(on: editor)

        if !editor.isDumb {
            print("\(cmd._commandName) interactive shell. Tab completes, `.form <cmd>` fills a command in, Ctrl-D quits.")
        }

        let session = editor
        await editor.readEvaluateLoop(prompt: "\(cmd._commandName) > ") { line in
            guard !line.isEmpty else { return .step }
            return await handle(input: line, editor: session)
        }
    }
}

public extension ParsableCommand {

    static var commandName: String { _commandName }

    /// Starts an interactive shell for this command tree.
    @MainActor
    static func readEvalPrintLoop() async throws {
        try await CommandREPLRunner(cmd: self).run()
    }
}
#endif
