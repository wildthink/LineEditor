//
//  LineEditor.swift
//  LineEditor
//
//  Created by Jason Jobe on 11/17/25.
//

import Foundation
import CLibEdit

public struct LineEditor {
    public init() {
        le_initialize()
    }

    public func readLine(prompt: String = "") -> String? {
        return prompt.withCString { cPrompt in
            guard let raw = le_readline(cPrompt) else { return nil } // EOF (Ctrl-D)
            defer { free(raw) }
            return String(cString: raw)
        }
    }

    public func addHistory(_ line: String) {
        line.withCString { le_add_history($0) }
    }

    public func clearHistory() {
        le_clear_history()
    }

    // Read/write persistent history to a file
    public func loadHistory(at path: String) throws {
        if le_read_history(path) != 0 {
            throw HistoryError.loadFailed(path)
        }
    }

    public func saveHistory(to path: String) throws {
        if le_write_history(path) != 0 {
            throw HistoryError.saveFailed(path)
        }
    }

    public enum HistoryError: Error, CustomStringConvertible {
        case loadFailed(String)
        case saveFailed(String)
        public var description: String {
            switch self {
            case .loadFailed(let p): return "Failed to read history: \(p)"
            case .saveFailed(let p): return "Failed to write history: \(p)"
            }
        }
    }

    @MainActor static var shared: CompletionBox?

    // Simple prefix-based completion from a Swift array
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

final class CompletionBox {
    private let words: [String]
    init(words: [String]) { self.words = words }
    func matches(prefix: String) -> [String] {
        words.filter { $0.hasPrefix(prefix) }
    }
}
