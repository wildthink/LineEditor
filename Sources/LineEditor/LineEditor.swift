//
//  LineEditor.swift
//  LineEditor
//
//  Created by Jason Jobe on 11/17/25.
//

import Foundation
import CLibEdit

/// A Swift wrapper around the CLibEdit line editor.
///
/// LineEditor provides readline-style input with optional history and simple
/// prefix-based tab completion, backed by the `CLibEdit` C library.
///
/// Typical usage:
/// ```swift
/// var editor = LineEditor()
/// try? editor.loadHistory(at: "/tmp/.repl_history")
/// editor.setCompletions(["help", "quit", "version"]) // optional
/// while let line = editor.readLine(prompt: "> ") {
///     if !line.isEmpty { editor.addHistory(line) }
///     if line == "quit" { break }
/// }
/// try? editor.saveHistory(to: "/tmp/.repl_history")
/// ```
///
/// - Note: The underlying C library is initialized in `init()` and completion
///   callbacks are installed via `setCompletions(_:)`.
public struct LineEditor {
    /// Creates a new line editor and initializes the underlying C library.
    public init() {
        le_initialize()
    }

    /// Reads a single line of input from the terminal.
    ///
    /// - Parameter prompt: The prompt to display before reading input.
    /// - Returns: The entered line as a `String`, or `nil` on EOF (for example, when the user presses Ctrl-D).
    public func readLine(prompt: String = "") -> String? {
        return prompt.withCString { cPrompt in
            guard let raw = le_readline(cPrompt) else { return nil } // EOF (Ctrl-D)
            defer { free(raw) }
            return String(cString: raw)
        }
    }

    /// Appends a line to the in-memory history buffer.
    ///
    /// - Parameter line: The line to record in history.
    public func addHistory(_ line: String) {
        line.withCString { le_add_history($0) }
    }

    /// Clears the in-memory history buffer.
    public func clearHistory() {
        le_clear_history()
    }

    /// Loads persistent history from a file.
    ///
    /// The file is parsed by the underlying library. Existing in-memory history
    /// is preserved and the file's entries are appended.
    ///
    /// - Parameter path: Path to the history file on disk.
    /// - Throws: ``LineEditor/HistoryError-swift.enum/loadFailed(_:)`` if the file cannot be read.
    public func loadHistory(at path: String) throws {
        if le_read_history(path) != 0 {
            throw HistoryError.loadFailed(path)
        }
    }

    /// Persists the current in-memory history to a file.
    ///
    /// - Parameter path: Destination path for the history file on disk.
    /// - Throws: ``LineEditor/HistoryError-swift.enum/saveFailed(_:)`` if the file cannot be written.
    public func saveHistory(to path: String) throws {
        if le_write_history(path) != 0 {
            throw HistoryError.saveFailed(path)
        }
    }

    /// Errors that can occur when loading or saving persistent history.
    public enum HistoryError: Error, CustomStringConvertible {
        /// Loading the history file at the given path failed.
        case loadFailed(String)
        /// Saving the history file to the given path failed.
        case saveFailed(String)
        public var description: String {
            switch self {
            case .loadFailed(let p): return "Failed to read history: \(p)"
            case .saveFailed(let p): return "Failed to write history: \(p)"
            }
        }
    }

    /// Shared storage for completion data retained for the lifetime of the process.
    ///
    /// - Warning: This is an internal implementation detail used by the C callback.
    @MainActor static var shared: CompletionBox?

    /// Configures simple prefix-based tab completion from a list of words.
    ///
    /// The provided words are retained for the lifetime of the process and exposed
    /// to the underlying C completion generator. Completion matches any word that
    /// has the given user-typed prefix.
    ///
    /// - Parameter words: Candidate words to be suggested when the user presses Tab.
    /// - Important: This installs a global C callback and retains its backing storage
    ///   via a shared box. Call this from the main actor.
    @MainActor public mutating func setCompletions(_ words: [String]) {
        // Hold onto Swift data and expose a C generator that strdup’s matches
        let box = CompletionBox(words: words)
        // Retain the box for the process lifetime by stashing it globally
        LineEditor.shared = box

        let generator: @convention(c) (UnsafePointer<CChar>?, Int32) -> UnsafeMutablePointer<CChar>? = { cText, state in
            let text = cText.map { String(cString: $0) } ?? ""
            let matches = LineEditor.shared?.matches(prefix: text) ?? []
            let idx = Int(state)
            guard idx < matches.count else { return nil }
            return strdup(matches[idx])
        }

        le_set_completion(generator)
    }
}

// MARK: - Completion storage

/// Internal storage for completion candidates and matching.
///
/// - Note: This type is an implementation detail and not part of the public API.
final class CompletionBox {
    private let words: [String]
    init(words: [String]) { self.words = words }
    func matches(prefix: String) -> [String] {
        words.filter { $0.hasPrefix(prefix) }
    }
}

/// Historical note: An earlier design placed the shared completion storage in
/// /// a separate `CompletionStore` enum. The current implementation keeps this
/// /// as a static on ``LineEditor`` to simplify symbol scoping and DocC links.
// enum CompletionStore {
//     @MainActor static var shared: CompletionBox?
// }
