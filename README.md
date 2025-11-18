# LineEditor

A tiny Swift wrapper around the system libedita.a line editor.
It provides interactive line input for terminal apps with history and
simple prefix-based tab completion — all from Swift.

Convience methods are provided to easily integrate ParsableCommands.

## Example Usage

Refer to [`repl.swift`](Sources/repl/repl.swift) for the complete example.

``` swift

struct MyParsableCommand: ParsableCommand {
    ...
}

struct ExampleLineEditor {
    
    @MainActor
    func run() {
        
        var editor = LineEditor()
        var history_file = "~/.example_history"
        
        // Load history file
        try? editor.loadHistory(at: history_file)
        
        // Provide some completions
        editor.setCompletions(["exit", "list", "load", "save"])
        
        print("LineEditor demo. Tab for completion, Ctrl-D to quit.")
        
        while let line = editor.readLine(prompt: "edit> ")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        {
            if !line.isEmpty { editor.addHistory(line) }
            if line == "exit" { break }
            let words = line.split(separator: " ")
            
            if words.first == "cmd" {
                do {
                    try MyParsableCommand.evaluate(argv: words.dropFirst())
                } catch {
                    MyParsableCommand.report(error: error)
                }
            } else {
                print("echo: \(line)")
            }
            
        }
        
        print("")
        
        // Save history on exit
        do { try editor.saveHistory(to: history_file) }
        catch {
            print("Warning: \(error)\n", stderr)
        }
    }
}

```

## Installation

You can add LineEditor to an Xcode project by adding it to your project as a package.

> https://github.com/wildthink/LineEditor

If you want to use LineEditor in a [SwiftPM](https://swift.org/package-manager/) 
project, it's as simple as adding it to your `Package.swift`:

``` swift
dependencies: [
  .package(url: "https://github.com/wildthink/LineEditor", from: "1.0.0")
]
```

And then adding the product to any target that needs access to the library:

```swift
.product(name: "LineEditor", package: "LineEditor"),
```
