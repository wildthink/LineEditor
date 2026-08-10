# LineEditor

Interactive line input for Swift terminal apps — history, cursor-aware tab
completion, and inline hints — plus a drop-in interactive shell for any
[swift-argument-parser](https://github.com/apple/swift-argument-parser) command
tree.

Backed by [bestline](https://github.com/mattt/bestline-swift), which vendors
Justine Tunney's single-file `bestline.c`. No system `libedit` needed.

## CommandREPL

Point `CommandREPLRunner` at a `ParsableCommand` and you get a shell that knows
your commands — derived entirely from the command definitions you already have.

```swift
struct Demo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "demo",
        subcommands: [Greet.self, Report.self])
}

@main
struct DemoMain {
    // A separate entry point: `AsyncParsableCommand` supplies its own `main()`,
    // which would otherwise win over an override declared on `Demo`.
    static func main() async throws {
        try await Demo.readEvalPrintLoop()
    }
}
```

That gets you:

- **Context-aware Tab completion.** Subcommands and aliases in command position;
  option names (suppressing non-repeating ones already used); enum cases from any
  `CaseIterable & ExpressibleByArgument` type, with their documentation; file
  completion filtered by extension; directory-only completion; `.shellCommand`
  sources; and `.custom` closures, run **in-process**.
- **Inline hints.** Dim text to the right of the cursor showing what the line
  still expects — `<subcommand>`, `<manifest>`, `<target> (required)`.
- **Guided forms.** `.form <command>` walks the command's arguments one field at
  a time, with per-field completion, numbered pickers for enums, `[y/N]` for
  flags, and repeat-until-blank for repeating options.
- **Async support.** Commands are dispatched through an async `evaluate(argv:)`,
  so `AsyncParsableCommand` trees actually run. (The synchronous path calls
  `ParsableCommand`'s default `run()`, which merely prints the help screen.)
- **Quote-aware parsing.** Arguments containing spaces survive, quoted or escaped.
- **Persistent history** in `~/.<command>_history`.

Everything above reads the `completion:` annotations you already declared for
shell completion. Nothing needs to be written twice.

### How it works

`ParsableArguments._dumpHelp()` is public API returning JSON in the versioned
`ToolInfoV0` schema, covering the whole subcommand tree. `CommandModel` decodes
it. No reflection, no private API.

`.custom` completions are reached through the parser's own reserved argv form
(`---completion … -- <arg> <index> <cursor> …`), whose result surfaces via the
public `message(for:)`. That means no subprocess and no cooperation from the
command being completed.

What the schema does *not* carry bounds what any consumer can do: there are no
static types (`defaultValue` is a `String`), `@OptionGroup` is flattened to a
section title, and cross-argument constraints live in `validate()` bodies and are
invisible. So a form builds an **argv** rather than binding values, and
`parseAsRoot` — which knows all of it — does the validating.

## Line editing on its own

```swift
struct ExampleLineEditor {
    @MainActor
    func run() {
        let editor = LineEditor(historyPrefix: "repl")
        editor.setCompletionProvider(
            PrefixCompletionProvider(words: ["help", "list", "load", "save"]))

        print("Tab for completion, Ctrl-D to quit.")

        editor.readEvaluateLoop(prompt: "repl > ") { line in
            if line == ".exit" { return .exit }
            print("echo: \(line)")
            return .step
        }
    }
}
```

Implement `CompletionProvider` for anything smarter. Providers return candidates
for the *token* under the cursor along with the span to replace; LineEditor
handles splicing into the full line and converting bestline's byte offsets to
character offsets.

```swift
public protocol CompletionProvider: Sendable {
    func complete(_ request: CompletionRequest) -> CompletionResult
    func hint(for line: String) -> String?   // optional
}
```

When `TERM` is `dumb`, every entry point falls back to `Swift.readLine()`, so
piped input and CI still work.

See [`repl.swift`](Sources/repl/repl.swift) for a demo exercising every
completion kind.

## Installation

```swift
dependencies: [
  .package(url: "https://github.com/wildthink/LineEditor", from: "2.0.0"),
]
```

```swift
.product(name: "CommandREPL", package: "LineEditor"),  // shell + line editing
.product(name: "LineEditor", package: "LineEditor"),   // line editing only
```

Requires macOS 15 and swift-argument-parser 1.8.0 or later.

## Migrating from 1.x

The line-editing API is source-compatible apart from completion:

- `setCompletions([String])` is deprecated but still works; it now installs a
  `PrefixCompletionProvider`. Prefer `setCompletionProvider(_:)`.
- `CommandREPLRunner.init` is now throwing (it introspects the command) and
  `run()` is `async`. `readEvalPrintLoop()` is likewise `async`.
- The `CLibEdit` target is gone; nothing links system `libedit` any more.
