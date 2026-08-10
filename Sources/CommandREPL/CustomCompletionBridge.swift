//
//  CustomCompletionBridge.swift
//  CommandREPL
//

import ArgumentParser
import ArgumentParserToolInfo
import Foundation

/// Invokes a command's `.custom` completion closures **in-process**.
///
/// `CommandParser` reserves an argv form for this (see its `handleCustomCompletion`):
///
/// ```
/// ---completion [<subcommand> ...] -- <arg-name> <arg-index> <cursor-index> [<args> ...]
/// ```
///
/// Parsing it throws `ParserError.completionScriptCustomResponse`, which the
/// public `message(for:)` renders as the newline-joined candidate list. That
/// makes the whole round trip reachable through public API with no subprocess
/// and no cooperation from the tool: any `completion: .custom { ... }` a command
/// already declares for shell completion works here unchanged.
///
/// Not supported: `.customAsync`, which returns nil on the parser's synchronous
/// path. Such arguments simply produce no candidates.
public enum CustomCompletionBridge {

    /// How the parser should look the argument back up.
    public enum ArgumentRef: Sendable {
        /// An option or flag, identified by a spelling such as `--only`.
        case named(String)
        /// A positional, identified by its zero-based ordinal.
        case positional(index: Int)

        var encoded: String {
            switch self {
            case .named(let name): return name
            case .positional(let index): return "positional@\(index)"
            }
        }
    }

    /// Runs the custom completion closure for one argument.
    ///
    /// - Parameters:
    ///   - root: The root command type, used to re-enter the parser.
    ///   - subcommandPath: Subcommand names leading to the argument's command.
    ///   - argument: Which argument's closure should run.
    ///   - argumentIndex: Index of the in-progress word within `words`.
    ///   - cursorIndex: Character offset of the cursor within the in-progress word.
    ///   - words: The words the closure sees, mirroring what a shell would pass.
    /// - Returns: Candidate strings, or `[]` if anything goes wrong. Completion
    ///   degrades silently rather than disrupting the prompt.
    public static func candidates<C: ParsableCommand>(
        root: C.Type,
        subcommandPath: [String],
        argument: ArgumentRef,
        argumentIndex: Int,
        cursorIndex: Int,
        words: [String]
    ) -> [String] {
        var argv = ["---completion"]
        argv += subcommandPath
        argv += ["--", argument.encoded, String(argumentIndex), String(cursorIndex)]
        argv += words

        // `CompletionShell.requesting` is read from SAP_SHELL. If it is set, the
        // parser formats results for that shell (adding descriptions, escaping)
        // instead of emitting a plain newline-separated list.
        return withoutShellEnvironment {
            do {
                _ = try root.parseAsRoot(argv)
                // A successful parse means the reserved form was not recognized.
                return []
            } catch {
                let text = root.message(for: error)
                guard !text.isEmpty else { return [] }
                return text
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .map(String.init)
            }
        }
    }

    /// Runs `body` with `SAP_SHELL` cleared, restoring it afterwards.
    private static func withoutShellEnvironment<T>(_ body: () -> T) -> T {
        let key = "SAP_SHELL"
        guard let saved = ProcessInfo.processInfo.environment[key] else {
            return body()
        }
        unsetenv(key)
        defer { setenv(key, saved, 1) }
        return body()
    }
}

public extension Optional where Wrapped == ArgumentInfoV0.CompletionKindV0 {
    /// True for completion kinds backed by a user closure this bridge can run.
    var isCustom: Bool {
        switch self {
        case .custom, .customDeprecated: return true
        default: return false
        }
    }
}
