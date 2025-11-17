// The Swift Programming Language
// https://docs.swift.org/swift-book
import Foundation
import LineEditor

@main
struct repl {
    static func main() {
        print("Hello, world!")
        
        func historyPath() -> String {
            let home = ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
            return "\(home)/.editcli_history"
        }
        
        var editor = LineEditor()
        
        // Load history file (ignore errors if missing)
        do { try editor.loadHistory(at: historyPath()) } catch { /* no-op */ }
        
        // Provide demo completions
        editor.setCompletions([
            "help", "hello", "halt", "history", "host", "hover",
            "exit", "list", "load", "save"
        ])
        
        print("Libedit demo. Tab for completion, Ctrl-D to quit.")
        while true {
            guard let line = editor.readLine(prompt: "edit> ") else {
                print("\nEOF. Bye.")
                break
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                editor.addHistory(trimmed)
            }
            if trimmed == "exit" { break }
            print("You typed: \(trimmed)")
        }
        
        // Save history on exit
        do { try editor.saveHistory(to: historyPath()) } catch {
            fputs("Warning: \(error)\n", stderr)
        }
    }
}

