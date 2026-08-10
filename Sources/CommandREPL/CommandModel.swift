//
//  CommandModel.swift
//  CommandREPL
//

import ArgumentParser
import ArgumentParserToolInfo
import Foundation

/// A structural description of a `ParsableCommand` tree.
///
/// Built from `ParsableArguments._dumpHelp()`, which is public API returning
/// JSON in the versioned `ToolInfoV0` schema and already recurses the whole
/// subcommand tree. No reflection or private API is involved.
///
/// Note what the schema deliberately does *not* carry, since it bounds what any
/// consumer can do:
///
/// - No static types. `defaultValue` is a `String` and `valueName` is a display
///   hint, so values can only be validated by attempting a real parse.
/// - `@OptionGroup` is flattened; grouping survives only as `sectionTitle`.
/// - Cross-argument constraints live in `validate()` bodies and are invisible.
/// - Note: `@unchecked Sendable` because the `ToolInfoV0` family predates
///   `Sendable` annotation. Those types are immutable trees of strings, arrays,
///   and enums with no reference storage, and this model never mutates one.
public struct CommandModel: @unchecked Sendable {
    /// The root command's info, including its full subcommand tree.
    public let root: CommandInfoV0

    /// Builds a model by introspecting `type`.
    ///
    /// - Throws: A `DecodingError` if the tool info schema is newer than this
    ///   package understands.
    public init<C: ParsableCommand>(_ type: C.Type) throws {
        let json = Data(type._dumpHelp().utf8)
        self.root = try JSONDecoder().decode(ToolInfoV0.self, from: json).command
    }

    public init(root: CommandInfoV0) {
        self.root = root
    }

    /// Walks `path` down the subcommand tree, matching names and aliases.
    ///
    /// Stops at the first element that names no subcommand, so a partially
    /// typed trailing word does not derail resolution.
    ///
    /// - Returns: The deepest command reached and the path elements consumed
    ///   getting there.
    public func resolve(path: [String]) -> (command: CommandInfoV0, consumed: [String]) {
        var current = root
        var consumed: [String] = []

        for element in path {
            guard let next = current.subcommands?.first(where: {
                $0.commandName == element || ($0.aliases?.contains(element) ?? false)
            }) else { break }
            current = next
            consumed.append(element)
        }

        return (current, consumed)
    }
}

// MARK: - Convenience accessors

public extension CommandInfoV0 {
    /// Subcommands that should appear in help and completion.
    var visibleSubcommands: [CommandInfoV0] {
        (subcommands ?? []).filter(\.shouldDisplay)
    }

    /// Arguments that should appear in help and completion.
    var visibleArguments: [ArgumentInfoV0] {
        (arguments ?? []).filter(\.shouldDisplay)
    }

    /// Arguments a form should prompt for.
    ///
    /// Excludes `--help` and `--version`, which ArgumentParser injects. They are
    /// actions that terminate parsing, not inputs to fill in, so prompting for
    /// them produces an argv that never runs the command.
    var formArguments: [ArgumentInfoV0] {
        visibleArguments.filter { !$0.isParserInjected }
    }

    /// Visible positional arguments, in declaration order.
    var positionals: [ArgumentInfoV0] {
        visibleArguments.filter { $0.kind == .positional }
    }

    /// Visible options and flags.
    var optionsAndFlags: [ArgumentInfoV0] {
        visibleArguments.filter { $0.kind != .positional }
    }

    /// Finds the option or flag matching a typed token such as `--only` or `-m`.
    func argument(matchingToken token: String) -> ArgumentInfoV0? {
        optionsAndFlags.first { $0.matchesToken(token) }
    }
}

public extension ArgumentInfoV0 {
    /// All spellings of this argument as they appear on a command line,
    /// e.g. `["-m", "--manifest"]`.
    var tokenNames: [String] {
        (names ?? []).map(\.token)
    }

    func matchesToken(_ token: String) -> Bool {
        tokenNames.contains(token)
    }

    /// True when this argument consumes a following value. Flags do not.
    var takesValue: Bool { kind == .option }

    /// True for the `--help` / `--version` flags ArgumentParser adds itself.
    ///
    /// Recognized by spelling, since the tool info schema does not distinguish
    /// injected arguments from declared ones. A command that declares its own
    /// flag under one of these names would be misclassified -- an acceptable
    /// trade, since ArgumentParser already reserves them.
    var isParserInjected: Bool {
        kind == .flag && !Set(tokenNames).isDisjoint(with: ["--help", "-h", "--version"])
    }

    /// The name to show in prompts and hints.
    var displayName: String {
        preferredName?.token ?? tokenNames.first ?? valueName ?? "argument"
    }

    /// The placeholder to show for this argument's value.
    var valuePlaceholder: String {
        valueName ?? displayName
    }
}

public extension ArgumentInfoV0.NameInfoV0 {
    /// The name as typed on a command line, with its leading dashes.
    var token: String {
        switch kind {
        case .long: return "--\(name)"
        case .short: return "-\(name)"
        case .longWithSingleDash: return "-\(name)"
        @unknown default: return name
        }
    }
}
