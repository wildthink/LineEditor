// The Swift Programming Language
// https://docs.swift.org/swift-book
import Foundation
import ArgumentParser
import LineEditor
import CommandREPL

struct CommandREPL: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "repl",
        abstract: "REPL provides an interactive shell for executing commands",
        version: "0.1.0"
    )

    @Option var name: String = "World"
    
    func run() throws {
        print("Hello", name)
    }
}

@main
struct repl {
    static func main() {
        
        var editor = LineEditor()
        
        func historyPath() -> String {
            let home = ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
            return "\(home)/.editcli_history"
        }
        
        // Load history file (ignore errors if missing)
        do { try editor.loadHistory(at: historyPath()) } catch { /* no-op */ }
        
        // Provide demo completions
        editor.setCompletions([
            "help", "hello", "halt", "history", "host", "hover",
            "exit", "list", "load", "save"
        ])
        
        print("Libedit demo. Tab for completion, Ctrl-D to quit.")
        while let line = editor.readLine(prompt: "edit> ")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        {
            if !line.isEmpty { editor.addHistory(line) }
            if line == "exit" { break }
            let words = line.split(separator: " ")
            if words.first == "cmd" {
                do {
                    try CommandREPL.evaluate(argv: words.dropFirst())
                } catch {
                    CommandREPL.report(error: error)
                }
            } else {
                print("echo: \(line)")
            }
            
        }
        print("")
        
        // Save history on exit
        do { try editor.saveHistory(to: historyPath()) } catch {
            fputs("Warning: \(error)\n", stderr)
        }
    }
}
