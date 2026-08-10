//
//  CommandForm.swift
//  CommandREPL
//

import ArgumentParser
import ArgumentParserToolInfo
import Foundation
import LineEditor

/// Where a form gets its answers.
///
/// `LineEditor` is the production conformance; tests supply a scripted one, so
/// argv assembly can be verified without a terminal.
public protocol FormInput {
    func readLine(prompt: String) -> String?
    func setCompletionProvider(_ provider: any CompletionProvider)
}

extension LineEditor: FormInput {}

/// Walks a user through one command's arguments and assembles an argv.
///
/// The form deliberately **builds an argument vector rather than binding
/// values**. Everything the introspected model cannot tell us -- an argument's
/// real type, whether two flags conflict, whether a required combination is
/// satisfied -- is left to `parseAsRoot`, which knows all of it. So a filled
/// form is validated by running it, and failures surface through the command's
/// own help and error messages.
///
/// Each field installs a completion provider scoped to that one argument, so
/// file, directory, enum, `.shellCommand`, and `.custom` completion all work
/// inside the form exactly as they do on the command line.
@MainActor
public struct CommandForm<Root: ParsableCommand> {
    let root: Root.Type
    let model: CommandModel
    /// Subcommand names leading to `command`.
    let path: [String]
    let command: CommandInfoV0

    public init(
        root: Root.Type,
        model: CommandModel,
        path: [String],
        command: CommandInfoV0
    ) {
        self.root = root
        self.model = model
        self.path = path
        self.command = command
    }

    /// Prompts for every visible argument.
    ///
    /// - Returns: The assembled argv, or `nil` if the user sent EOF.
    public func run(editor: some FormInput) -> [String]? {
        if let abstract = command.abstract, !abstract.isEmpty {
            print("\n\(dim(abstract))")
        }
        print(dim("Return accepts the default; blank skips an optional argument."))

        var options: [String] = []
        var positionals: [String] = []
        var positionalIndex = 0

        for argument in command.formArguments {
            if let caption = argument.abstract, !caption.isEmpty {
                print("\n\(dim(caption))")
            }

            switch argument.kind {
            case .flag:
                guard let enabled = askFlag(argument, editor: editor) else { return nil }
                if enabled, let name = argument.preferredName?.token ?? argument.tokenNames.first {
                    options.append(name)
                }

            case .option:
                guard let values = askValues(
                    argument, editor: editor, positionalIndex: nil
                ) else { return nil }
                let name = argument.preferredName?.token ?? argument.tokenNames.first
                for value in values {
                    if let name { options.append(name) }
                    options.append(value)
                }

            case .positional:
                guard let values = askValues(
                    argument, editor: editor, positionalIndex: positionalIndex
                ) else { return nil }
                positionals += values
                positionalIndex += 1

            @unknown default:
                continue
            }
        }

        var argv = path + options
        if !positionals.isEmpty {
            // A terminator is only needed when a positional could be mistaken
            // for an option.
            if positionals.contains(where: { $0.hasPrefix("-") }) {
                argv.append("--")
            }
            argv += positionals
        }
        return argv
    }

    // MARK: - Fields

    private func askFlag(_ argument: ArgumentInfoV0, editor: some FormInput) -> Bool? {
        let defaultsOn = argument.defaultValue == "true"
        let choices = defaultsOn ? "[Y/n]" : "[y/N]"
        editor.setCompletionProvider(PrefixCompletionProvider(words: ["yes", "no"]))

        while true {
            guard let answer = editor.readLine(
                prompt: "\(argument.displayName) \(choices): "
            )?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }

            if answer.isEmpty { return defaultsOn }
            if ["y", "yes", "true", "1"].contains(answer) { return true }
            if ["n", "no", "false", "0"].contains(answer) { return false }
            print(dim("Please answer y or n."))
        }
    }

    /// Prompts for one argument's value(s), looping while `isRepeating`.
    private func askValues(
        _ argument: ArgumentInfoV0,
        editor: some FormInput,
        positionalIndex: Int?
    ) -> [String]? {
        editor.setCompletionProvider(
            CommandCompletionProvider(
                root: root,
                model: model,
                scope: .init(
                    subcommandPath: path,
                    command: command,
                    argument: argument,
                    positionalIndex: positionalIndex
                )
            )
        )

        if let choices = argument.allValues, !choices.isEmpty {
            print(dim("Choices:"))
            for (i, choice) in choices.enumerated() {
                let detail = argument.allValueDescriptions?[choice].map { " — \($0)" } ?? ""
                print(dim("  \(i + 1). \(choice)\(detail)"))
            }
        }

        var values: [String] = []
        while true {
            let ordinal = argument.isRepeating && !values.isEmpty ? " (\(values.count + 1))" : ""
            guard let entry = editor.readLine(prompt: prompt(for: argument) + ordinal + ": ")
            else { return nil }

            let trimmed = entry.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                // Blank ends a repeating list, or skips a single-value argument.
                if !argument.isRepeating, !argument.isOptional, values.isEmpty {
                    print(dim("This argument is required."))
                    continue
                }
                return values
            }

            values.append(resolve(trimmed, against: argument))
            if !argument.isRepeating { return values }
        }
    }

    /// Lets the user answer an enumerated argument by number as well as by name.
    private func resolve(_ entry: String, against argument: ArgumentInfoV0) -> String {
        guard let choices = argument.allValues, !choices.isEmpty,
              let index = Int(entry), index >= 1, index <= choices.count
        else { return entry }
        return choices[index - 1]
    }

    private func prompt(for argument: ArgumentInfoV0) -> String {
        var text = argument.displayName
        if argument.kind == .positional {
            text = "<\(argument.valuePlaceholder)>"
        }
        if let value = argument.defaultValue, !value.isEmpty {
            text += " [\(value)]"
        } else if argument.isOptional {
            text += " (optional)"
        }
        if argument.isRepeating {
            text += " (blank to finish)"
        }
        return text
    }

    private func dim(_ text: String) -> String {
        // Skip escapes when output is redirected.
        guard isatty(STDOUT_FILENO) == 1 else { return text }
        return "\u{1B}[2m\(text)\u{1B}[0m"
    }
}
