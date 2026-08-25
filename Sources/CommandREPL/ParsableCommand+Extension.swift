//
//  CommandREPL.swift
//  LineEditor
//
//  Created by Jason Jobe on 11/18/25.
//

#if canImport(ArgumentParser)
import ArgumentParser
import Foundation

/// Convenience evaluation APIs for ArgumentParser commands.
///
/// This extension adds a family of `evaluate` helpers that parse and run a
/// `ParsableCommand` from different argument representations commonly produced
/// by REPLs and line editors. Overloads accept a raw command line string,
/// string subsequences from tokenization, and generic `StringProtocol`
/// collections, all funneled into a canonical `[String]` for parsing.
///
/// In case of parsing errors, `report(error:)` prints the error the way
/// ArgumentParser's own `exit(withError:)` does: the message and its usage line, on
/// standard error when the error is a genuine failure. Use `helpMessage(for:maxColumns:)`
/// instead when what you want is the help screen for the command that failed.
public extension ParsableCommand {

    /// Parses and runs the command from an array of string Sequences.
    ///
    /// The input is expected to mirror `CommandLine.arguments`
    /// and also captures and prints any errors
    ///
    /// - Parameter argv: Pre-tokenized arguments as string subsequences.
    static func evaluateAsRoot(argv: some Sequence<some StringProtocol>) {
        do {
            try evaluate(argv: Array(argv))
        } catch {
            report(error: error)
        }
    }

    /// Parses and runs the command from a single command line string.
    ///
    /// The string is split on spaces to form an argument vector and then parsed
    /// with `ArgumentParser`. Quoted or escaped argument handling is not performed
    /// here; pass a pre-tokenized array if you need custom tokenization.
    ///
    /// - Parameter line: A single line containing the command and its arguments,
    ///   separated by spaces.
    /// - Throws: An error if parsing fails or if `run()` throws.
    static func evaluate(line: String) throws {
        let argv = line.split(separator: " ")
        try evaluate(argv: argv)
    }
    
    /// Parses and runs the command from an array of string Sequences.
    ///
    /// Use this overload when your tokenizer yields `SubSequence<String>` tokens.
    /// The tokens are converted to `String` and forwarded to the primary
    /// `[String]` overload.
    ///
    /// - Parameter argv: Pre-tokenized arguments as string subsequences.
    /// - Throws: An error if parsing fails or if `run()` throws.
    static func evaluate(argv: some Sequence<String>) throws {
        try evaluate(argv: argv.map { String($0) })
    }

    /// Parses and runs the command from an array of `StringProtocol` values.
    ///
    /// This generic convenience overload accepts any collection of strings
    /// conforming to `StringProtocol` and forwards them as `Sequence<String>`.
    ///
    /// - Parameter argv: Pre-tokenized arguments as `StringProtocol` values.
    /// - Throws: An error if parsing fails or if `run()` throws.
    static func evaluate<S: StringProtocol>(argv: Sequence<S>) throws {
        try evaluate(argv: argv.map { String($0) })
    }
    
    /// Parses and runs the command from an array of strings.
    ///
    /// This is the primary entry point used by the other overloads. It calls
    /// `Self.parseAsRoot(_:)` to construct the command and then invokes `run()`.
    ///
    /// - Parameter argv: The argument vector, where the first element is typically
    ///   the subcommand name (if any) followed by options and operands.
    /// - Throws: An error if parsing fails or if `run()` throws.
    static func evaluate(argv: [String]) throws {
        var cmd = try Self.parseAsRoot(argv)
        try cmd.run()
    }

    /// Parses and runs the command, awaiting `run()` when the resolved command
    /// is asynchronous.
    ///
    /// Prefer this over the synchronous overload whenever the command tree
    /// contains any `AsyncParsableCommand`. `ParsableCommand` supplies a default
    /// synchronous `run()` that merely prints the help screen, so calling the
    /// sync path on an async command silently does nothing useful.
    ///
    /// Note that the resolved command may be async even when `Self` is not --
    /// only the subcommand that actually parsed matters, so the check happens on
    /// the parsed instance rather than on `Self`.
    ///
    /// - Parameter argv: The argument vector, where the first element is typically
    ///   the subcommand name (if any) followed by options and operands.
    /// - Throws: An error if parsing fails or if `run()` throws.
    static func evaluate(argv: [String]) async throws {
        let cmd = try Self.parseAsRoot(argv)
        if var asyncCommand = cmd as? AsyncParsableCommand {
            try await asyncCommand.run()
        } else {
            var syncCommand = cmd
            try syncCommand.run()
        }
    }

    /// Parses and runs the command from a single line, awaiting async commands.
    ///
    /// The line is tokenized with ``Tokenizer``, so quoted arguments and escaped
    /// spaces survive -- unlike the synchronous ``evaluate(line:)``, which splits
    /// naively on spaces.
    static func evaluate(line: String) async throws {
        try await evaluate(argv: Tokenizer.tokens(in: line).map(\.text))
    }

    /// Parses and runs the command, reporting any error rather than throwing.
    static func evaluateAsRoot(argv: [String]) async {
        do {
            try await evaluate(argv: argv)
        } catch {
            report(error: error)
        }
    }

    /// Returns a formatted help message for a parsing error.
    ///
    /// If the provided `error` contains an ArgumentParser command type stack,
    /// this method renders the help message for the last command in the stack.
    /// Otherwise, it returns a fallback string that includes the error's
    /// localized description.
    ///
    /// - Parameters:
    ///   - error: The error produced during parsing or execution.
    ///   - maxColumns: The maximum width used when formatting the help message.
    /// - Returns: A help string suitable for displaying to the user.
    static func helpMessage(for error: Error, maxColumns: Int = 80) -> String {
        let m = Mirror(reflecting: error)

        if error is CleanExit {
            if let helpRequest = m.descendant("base", "helpRequest"),
               let pt = helpRequest as? ParsableCommand.Type
            {
                return pt.helpMessage()
            }
        }

        for c in m.children {
            switch c.value {
                case let stack as [ParsableCommand.Type]:
                    if let last = stack.last {
                        var str = ""
                        print(last.helpMessage(columns: maxColumns), to: &str)
                        return str.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                default:
                    break
            }
        }
        return "\(self._commandName) - \(error)"
    }
    
    /// The text ``report(error:)`` prints for `error`, and where it belongs.
    ///
    /// Split out so an embedder that renders errors itself -- a GUI shell, a log, a
    /// transcript -- can get the same text without printing, and so the routing can be
    /// tested without capturing file descriptors.
    ///
    /// - Parameter error: The error produced during parsing or execution.
    /// - Returns: The message and whether it describes a failure, or `nil` when there is
    ///   nothing to print.
    static func reportMessage(for error: Error) -> (text: String, isFailure: Bool)? {
        let text = fullMessage(for: error)
        guard !text.isEmpty else { return nil }
        return (text, exitCode(for: error) != .success)
    }

    /// Prints `error` the way ArgumentParser's own `exit(withError:)` does, minus the exiting.
    ///
    /// A clean exit -- `--help`, `--version`, an explicit `CleanExit.message` -- goes to
    /// standard output; anything else goes to standard error. A bare `ExitCode` prints
    /// nothing, because the command that threw it has already written its own message.
    ///
    /// This reports through `fullMessage(for:)` rather than ``helpMessage(for:maxColumns:)``.
    /// A help screen alone drops the error text -- the half that names the offending value
    /// and lists the ones that are accepted -- which is the half worth reading when an option
    /// is typed by hand. ``helpMessage(for:maxColumns:)`` remains available for callers that
    /// want the screen instead.
    ///
    /// - Parameter error: The error produced during parsing or execution.
    static func report(error: Error) {
        guard let report = reportMessage(for: error) else { return }
        if report.isFailure {
            FileHandle.standardError.write(Data((report.text + "\n").utf8))
        } else {
            print(report.text)
        }
    }
}
#endif

