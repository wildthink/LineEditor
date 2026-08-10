//
//  CommandCompletionProvider.swift
//  CommandREPL
//

import ArgumentParser
import ArgumentParserToolInfo
import Foundation
import LineEditor

/// Drives Tab completion and inline hints for a `ParsableCommand` tree.
///
/// Resolution proceeds in a fixed order:
///
/// 1. Tokenize the line and walk to the deepest subcommand named before the cursor.
/// 2. Still in subcommand position -> subcommand names, aliases, and meta-commands.
/// 3. Previous token is an option expecting a value -> that option's value source.
/// 4. Current token starts with `-` -> option spellings not already used.
/// 5. Otherwise -> the positional at the current index -> its value source.
public struct CommandCompletionProvider<Root: ParsableCommand>: CompletionProvider {

    let model: CommandModel
    /// Extra words offered alongside subcommands, e.g. `.exit` and `.form`.
    let metaCommands: [String]
    /// When set, completion is confined to a single argument. Used by
    /// ``CommandForm`` so each field gets the right candidates for its own value.
    let scope: Scope?

    /// Narrows completion to one argument of one command.
    ///
    /// - Note: `@unchecked Sendable` for the same reason as ``CommandModel``.
    public struct Scope: @unchecked Sendable {
        public var subcommandPath: [String]
        public var command: CommandInfoV0
        public var argument: ArgumentInfoV0
        public var positionalIndex: Int?

        public init(
            subcommandPath: [String],
            command: CommandInfoV0,
            argument: ArgumentInfoV0,
            positionalIndex: Int? = nil
        ) {
            self.subcommandPath = subcommandPath
            self.command = command
            self.argument = argument
            self.positionalIndex = positionalIndex
        }
    }

    public init(
        root: Root.Type,
        model: CommandModel,
        metaCommands: [String] = [],
        scope: Scope? = nil
    ) {
        self.model = model
        self.metaCommands = metaCommands
        self.scope = scope
    }

    // MARK: - CompletionProvider

    public func complete(_ request: CompletionRequest) -> CompletionResult {
        let (completed, partial) = Tokenizer.split(request.line, cursor: request.cursor)
        let prefix = partial?.text ?? ""
        let replacingFrom = partial?.start ?? request.cursor

        // Field-scoped: the whole line is one argument's value.
        if let scope {
            let candidates = values(
                for: scope.argument,
                command: scope.command,
                subcommandPath: scope.subcommandPath,
                positionalIndex: scope.positionalIndex,
                prefix: prefix,
                words: completed.map(\.text) + [prefix]
            )
            return CompletionResult(replacingFrom: replacingFrom, candidates: candidates)
        }

        let words = completed.map(\.text)
        let (command, consumed) = model.resolve(path: words)

        // 2. Subcommand position: everything typed so far was consumed as a path
        //    and this command still has children to offer.
        if consumed.count == words.count, !command.visibleSubcommands.isEmpty {
            var candidates = command.visibleSubcommands
                .filter { $0.commandName.hasPrefix(prefix) }
                .map { Completion($0.commandName, detail: $0.abstract) }
            candidates += metaCommands
                .filter { $0.hasPrefix(prefix) }
                .map { Completion($0) }
            if !candidates.isEmpty || !prefix.hasPrefix("-") {
                return CompletionResult(replacingFrom: replacingFrom, candidates: candidates)
            }
        }

        let argumentWords = Array(words.dropFirst(consumed.count))

        // 3. The previous token is an option still waiting for its value.
        if let last = argumentWords.last,
           last.hasPrefix("-"),
           let option = command.argument(matchingToken: last),
           option.takesValue
        {
            let candidates = values(
                for: option,
                command: command,
                subcommandPath: consumed,
                positionalIndex: nil,
                prefix: prefix,
                words: argumentWords + [prefix]
            )
            return CompletionResult(replacingFrom: replacingFrom, candidates: candidates)
        }

        // 4. Typing an option name.
        if prefix.hasPrefix("-") {
            let used = Set(argumentWords.filter { $0.hasPrefix("-") })
            let candidates = command.optionsAndFlags
                .filter { argument in
                    // Repeating options may be offered again.
                    argument.isRepeating || !argument.tokenNames.contains(where: used.contains)
                }
                .flatMap { argument in
                    argument.tokenNames
                        .filter { $0.hasPrefix(prefix) }
                        .map { Completion($0, detail: argument.abstract) }
                }
            return CompletionResult(replacingFrom: replacingFrom, candidates: candidates)
        }

        // 5. A positional value.
        let index = positionalIndex(in: argumentWords, command: command)
        let positionals = command.positionals
        guard index < positionals.count else {
            return CompletionResult(replacingFrom: replacingFrom, candidates: [])
        }
        let candidates = values(
            for: positionals[index],
            command: command,
            subcommandPath: consumed,
            positionalIndex: index,
            prefix: prefix,
            words: argumentWords + [prefix]
        )
        return CompletionResult(replacingFrom: replacingFrom, candidates: candidates)
    }

    public func hint(for line: String) -> String? {
        guard scope == nil else { return nil }
        // Only hint at a clean token boundary; mid-word the user is still typing.
        guard line.isEmpty || line.hasSuffix(" ") else { return nil }

        let words = Tokenizer.tokens(in: line).map(\.text)
        let (command, consumed) = model.resolve(path: words)

        if consumed.count == words.count, !command.visibleSubcommands.isEmpty {
            return " <subcommand>"
        }

        let argumentWords = Array(words.dropFirst(consumed.count))

        if let last = argumentWords.last,
           last.hasPrefix("-"),
           let option = command.argument(matchingToken: last),
           option.takesValue
        {
            return " <\(option.valuePlaceholder)>"
        }

        let index = positionalIndex(in: argumentWords, command: command)
        let positionals = command.positionals
        if index < positionals.count {
            let positional = positionals[index]
            let optionality = positional.isOptional ? "" : " (required)"
            return " <\(positional.valuePlaceholder)>\(optionality)"
        }

        // Nothing required left: surface the most useful remaining option.
        if let next = command.optionsAndFlags.first(where: { argument in
            !argumentWords.contains(where: argument.matchesToken)
        }) {
            return " [\(next.displayName)]"
        }
        return nil
    }

    // MARK: - Value sources

    /// Counts how many positional values have already been supplied, skipping
    /// option names and the values they consume.
    private func positionalIndex(in words: [String], command: CommandInfoV0) -> Int {
        var index = 0
        var i = 0
        while i < words.count {
            let word = words[i]
            if word == "--" {
                // Everything after a terminator is positional.
                index += words.count - i - 1
                break
            }
            if word.hasPrefix("-"), word.count > 1 {
                if let option = command.argument(matchingToken: word), option.takesValue {
                    i += 2
                } else {
                    i += 1
                }
                continue
            }
            index += 1
            i += 1
        }
        return index
    }

    /// Produces candidates for one argument's value, from `allValues` and
    /// `completionKind`.
    private func values(
        for argument: ArgumentInfoV0,
        command: CommandInfoV0,
        subcommandPath: [String],
        positionalIndex: Int?,
        prefix: String,
        words: [String]
    ) -> [Completion] {
        // Enum cases and explicit value lists take precedence -- they are exact
        // and cheap, and ArgumentParser populates `allValues` for any
        // `CaseIterable & ExpressibleByArgument` type.
        var listed: [String] = argument.allValues ?? []
        if case .list(let values) = argument.completionKind {
            listed = values
        }
        if !listed.isEmpty {
            return listed
                .filter { $0.hasPrefix(prefix) }
                .map { Completion($0, detail: argument.allValueDescriptions?[$0]) }
        }

        switch argument.completionKind {
        case .file(let extensions):
            return paths(matching: prefix, extensions: extensions, directoriesOnly: false)

        case .directory:
            return paths(matching: prefix, extensions: [], directoriesOnly: true)

        case .shellCommand(let command):
            return shellCandidates(command: command, prefix: prefix)

        case .custom, .customDeprecated:
            let ref: CustomCompletionBridge.ArgumentRef =
                positionalIndex.map { .positional(index: $0) }
                ?? .named(argument.preferredName?.token ?? argument.displayName)
            return CustomCompletionBridge.candidates(
                root: Root.self,
                subcommandPath: subcommandPath,
                argument: ref,
                argumentIndex: max(0, words.count - 1),
                cursorIndex: prefix.count,
                words: words
            )
            .filter { $0.hasPrefix(prefix) }
            .map { Completion($0) }

        default:
            return []
        }
    }

    /// Filesystem completion over the directory implied by `prefix`.
    private func paths(
        matching prefix: String,
        extensions: [String],
        directoriesOnly: Bool
    ) -> [Completion] {
        let fm = FileManager.default

        // Expand `~` by hand rather than with `NSString.expandingTildeInPath`,
        // which also normalizes the path and strips a trailing slash. That
        // distinction is load-bearing here: `/dir/` means "list dir" while
        // `/dir` means "match entries named dir* in its parent".
        let expanded: String
        if prefix == "~" {
            expanded = NSHomeDirectory()
        } else if prefix.hasPrefix("~/") {
            expanded = NSHomeDirectory() + prefix.dropFirst(1)
        } else {
            expanded = prefix
        }

        // Split the typed text into "directory to list" and "name prefix to match".
        let directory: String
        let namePrefix: String
        if let slash = expanded.lastIndex(of: "/") {
            directory = String(expanded[...slash])
            namePrefix = String(expanded[expanded.index(after: slash)...])
        } else {
            directory = fm.currentDirectoryPath + "/"
            namePrefix = expanded
        }

        guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { return [] }

        // Preserve whatever the user typed (`~/`, a relative path) rather than
        // replacing it with the absolute path we listed.
        let displayDirectory: String = {
            guard let slash = prefix.lastIndex(of: "/") else { return "" }
            return String(prefix[...slash])
        }()

        return entries
            .filter { $0.hasPrefix(namePrefix) }
            .filter { !namePrefix.isEmpty || !$0.hasPrefix(".") }
            .compactMap { name -> Completion? in
                var isDirectory: ObjCBool = false
                let full = directory + name
                guard fm.fileExists(atPath: full, isDirectory: &isDirectory) else { return nil }
                if isDirectory.boolValue {
                    return Completion(Tokenizer.quoteIfNeeded(displayDirectory + name + "/"))
                }
                guard !directoriesOnly else { return nil }
                if !extensions.isEmpty {
                    let ext = (name as NSString).pathExtension
                    guard extensions.contains(ext) else { return nil }
                }
                return Completion(Tokenizer.quoteIfNeeded(displayDirectory + name))
            }
            .sorted { $0.value < $1.value }
    }

    /// Runs a `.shellCommand` completion source and splits its output on newlines.
    private func shellCandidates(command: String, prefix: String) -> [Completion] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()

        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0.hasPrefix(prefix) }
            .map { Completion($0) }
    }
}
