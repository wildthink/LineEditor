# LineEditor

A tiny Swift wrapper around the system libedita.a line editor.
It provides interactive line input for terminal apps with history and
simple prefix-based tab completion — all from Swift.

Convience methods are provided to easily integrate ParsableCommands.

## Example Usage

Refer to [`repl.swift`](Sources/repl/repl.swift) for the complete example.

The `CommandREPLRunner` makes it easy to wrap your `ParsableCommands` with
and interactive REPL.

``` swift

struct HelloWorld: ParsableCommand {
    ...
}

@main
struct DemoMain {
    static func main() throws {
        try CommandREPLRunner(cmd: HelloWorld.self).run()
    }
}
```

Or you can easily "roll-your-own" evaluater loop.

``` swift
struct ExampleLineEditor {
    
    @MainActor
    func run() {
        var editor = LineEditor(historyPrefix: "repl")
        
        /// Configure a small set of completion candidates for demonstration.
        editor.setCompletions([
            "help", "hello", "halt", "history", "host", "hover",
            "exit", "list", "load", "save"
        ])
        
        print("Libedit demo. Tab for completion, Ctrl-D to quit.")
        
        /// Read, evaluate, and print loop.
        /// - Exits on `.exit`
        editor.readEvaluateLoop(prompt: "repl > ") { line in
            if line == ".exit" { return .exit }
            print("echo: \(line)")
            return .step
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
  .package(url: "https://github.com/wildthink/LineEditor", from: "1.0.4"),
]
```

And then adding the product to any target that needs access to the library:

```swift
    .product(name: "LineEditor", package: "LineEditor"),
```
