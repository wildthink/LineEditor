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
/// In case of parsing errors, use `helpMessage(for:maxColumns:)` to retrieve a
/// formatted help message for the command that failed, or `report(error:)` to
/// print it directly.
public extension ParsableCommand {
        
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
    
    /// Parses and runs the command from an array of string subsequences.
    ///
    /// Use this overload when your tokenizer yields `String.SubSequence` tokens.
    /// The tokens are converted to `String` and forwarded to the primary
    /// `[String]` overload.
    ///
    /// - Parameter argv: Pre-tokenized arguments as string subsequences.
    /// - Throws: An error if parsing fails or if `run()` throws.
    static func evaluate(argv: [String.SubSequence]) throws {
        try evaluate(argv: argv.map { String($0) })
    }

    /// Parses and runs the command from a slice of string subsequences.
    ///
    /// This is useful when working with slices of a larger token array without
    /// copying. The slice is mapped to `String` and forwarded to the primary
    /// `[String]` overload.
    ///
    /// - Parameter argv: A slice of pre-tokenized arguments.
    /// - Throws: An error if parsing fails or if `run()` throws.
    static func evaluate(argv: Array<String.SubSequence>.SubSequence) throws {
        try evaluate(argv: argv.map { String($0) })
    }

    /// Parses and runs the command from an array of `StringProtocol` values.
    ///
    /// This generic convenience overload accepts any collection of strings
    /// conforming to `StringProtocol` and forwards them as `[String]`.
    ///
    /// - Parameter argv: Pre-tokenized arguments as `StringProtocol` values.
    /// - Throws: An error if parsing fails or if `run()` throws.
    static func evaluate<S: StringProtocol>(argv: [S]) throws {
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
        for c in m.children {
            switch c.value {
                case let stack as [ParsableCommand.Type]:
                    if let last = stack.last {
                        var str = ""
                        print(last.helpMessage(columns: maxColumns), to: &str)
                        return str
                    }
                default:
                    break
            }
        }
        return "No help available for \(error.localizedDescription)"
    }
    
    /// Prints a help message for an error to standard output.
    ///
    /// This is a convenience wrapper around `helpMessage(for:)` that writes the
    /// resulting text to the default output stream.
    ///
    /// - Parameter error: The error produced during parsing or execution.
    static func report(error: Error) {
        print(helpMessage(for: error))
    }
}
#endif

