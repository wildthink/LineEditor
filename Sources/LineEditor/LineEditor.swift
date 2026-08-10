//
//  LineEditor.swift
//  LineEditor
//
//  Created by Jason Jobe on 11/17/25.
//

import Foundation
import Bestline

/// A Swift wrapper around the bestline line editor.
///
/// LineEditor provides readline-style input with optional history, cursor-aware
/// tab completion, and inline hints.
///
/// Typical usage:
/// ```swift
/// var editor = LineEditor()
/// try? editor.loadHistory(at: "/tmp/.repl_history")
/// editor.setCompletionProvider(MyProvider())      // optional
/// while let line = editor.readLine(prompt: "> ") {
///     if !line.isEmpty { editor.addHistory(line) }
///     if line == "quit" { break }
/// }
/// try? editor.saveHistory(to: "/tmp/.repl_history")
/// ```
///
/// - Note: Completion and hint callbacks are process-global in the underlying C
///   library. Installing a provider replaces whatever was installed before.
public struct LineEditor {

    public var historyFile: String?
    public var terminal: String {
        ProcessInfo.processInfo.environment["TERM"] ?? "dumb"
    }

    /// True when the terminal cannot support interactive editing, in which case
    /// every entry point falls back to `Swift.readLine()`.
    public var isDumb: Bool { terminal == "dumb" }

    /// Creates a new line editor.
    public init(historyFile: String? = nil) {
        self.historyFile = historyFile
    }

    /// Emits a terminal bell.
    public func ding() {
        FileHandle.standardError.write(Data([0x07]))
    }

    /// Reads a single line of input from the terminal.
    ///
    /// - Parameter prompt: The prompt to display before reading input.
    /// - Returns: The entered line as a `String`, or `nil` on EOF (for example, when the user presses Ctrl-D).
    public func readLine(prompt: String = "") -> String? {
        if isDumb {
            print(prompt, terminator: "")
            return Swift.readLine()
        }
        return Bestline.readLine(prompt: prompt)
    }

    /// Reads a line with the edit buffer pre-populated.
    ///
    /// Used by form-style prompts to offer a default the user can accept with
    /// Return or edit in place.
    ///
    /// - Parameters:
    ///   - prompt: The prompt to display before reading input.
    ///   - initialText: Text placed in the edit buffer before reading.
    /// - Returns: The entered line, or `nil` on EOF.
    public func readLine(prompt: String, initialText: String) -> String? {
        guard !initialText.isEmpty else { return readLine(prompt: prompt) }
        if isDumb {
            print("\(prompt)[\(initialText)] ", terminator: "")
            guard let entered = Swift.readLine() else { return nil }
            return entered.isEmpty ? initialText : entered
        }
        return Bestline.readLine(prompt: prompt, initialText: initialText)
    }

    /// Appends a line to the in-memory history buffer.
    ///
    /// - Parameter line: The line to record in history.
    public func addHistory(_ line: String) {
        _ = Bestline.addToHistory(line)
    }

    /// Clears the in-memory history buffer.
    public func clearHistory() {
        Bestline.freeHistory()
    }

    /// Loads persistent history from a file.
    ///
    /// - Parameter path: Path to the history file on disk.
    /// - Throws: ``LineEditor/HistoryError-swift.enum/loadFailed(_:)`` if the file cannot be read.
    public func loadHistory(at path: String) throws {
        // A missing history file is the normal first-run case, not an error.
        guard FileManager.default.fileExists(atPath: path) else { return }
        if !Bestline.loadHistory(from: path) {
            throw HistoryError.loadFailed(path)
        }
    }

    /// Persists the current in-memory history to a file.
    ///
    /// - Parameter path: Destination path for the history file on disk.
    /// - Throws: ``LineEditor/HistoryError-swift.enum/saveFailed(_:)`` if the file cannot be written.
    public func saveHistory(to path: String) throws {
        if !Bestline.saveHistory(to: path) {
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

    // MARK: - Completion

    /// Installs a completion provider, replacing any previously installed one.
    ///
    /// The provider drives both Tab completion and inline hints. Because the
    /// underlying callbacks are process-global, the provider is retained for the
    /// lifetime of the process (or until replaced).
    public func setCompletionProvider(_ provider: any CompletionProvider) {
        guard !isDumb else { return }
        CompletionBridge.install(provider)
    }

    /// Configures simple prefix-based tab completion from a list of words.
    ///
    /// - Parameter words: Candidate words to be suggested when the user presses Tab.
    @available(*, deprecated, message: "Use setCompletionProvider(_:) with a CompletionProvider.")
    public mutating func setCompletions(_ words: [String]) {
        setCompletionProvider(PrefixCompletionProvider(words: words))
    }
}

// MARK: - Completion bridge

/// Adapts a ``CompletionProvider`` to bestline's C callbacks.
///
/// Two impedance mismatches are handled here so providers never see them:
///
/// 1. bestline reports the cursor as a **byte** offset into the UTF-8 buffer,
///    while the provider API is expressed in Character offsets.
/// 2. An accepted completion **replaces the entire line** (bestline.c does
///    `memcpy(ls->buf, cvec[i], n + 1)` and then moves the cursor by the length
///    delta). Providers return only the token text, and this bridge splices it
///    into `prefix + token + suffix`. The splice is confined to text at or
///    before the cursor, which is what makes bestline's delta arithmetic land
///    the cursor in the right place.
enum CompletionBridge {
    /// Retained for the process lifetime because the C callbacks are global.
    nonisolated(unsafe) private static var current: (any CompletionProvider)?

    static func install(_ provider: any CompletionProvider) {
        current = provider

        Bestline.setCompletionCallback { line, byteCursor in
            guard let provider = current else { return [] }
            return replacementLines(for: line, byteCursor: byteCursor, provider: provider)
        }

        Bestline.setHintsCallback { line in
            current?.hint(for: line)
        }
    }

    /// Builds the full-line replacements bestline expects from a provider's
    /// token-level candidates.
    ///
    /// Separated from the callback so it can be tested without a terminal --
    /// this is the seam where an off-by-one silently corrupts the user's line.
    static func replacementLines(
        for line: String,
        byteCursor: Int,
        provider: any CompletionProvider
    ) -> [String] {
        let cursor = characterOffset(in: line, forByteOffset: byteCursor)
        let result = provider.complete(CompletionRequest(line: line, cursor: cursor))
        guard !result.candidates.isEmpty else { return [] }

        let clamped = max(0, min(result.replacingFrom, cursor))
        let head = String(line.prefix(clamped))
        let tail = String(line.dropFirst(cursor))
        return result.candidates.map { head + $0.value + tail }
    }

    /// Converts a UTF-8 byte offset into a Character offset, clamping to the
    /// nearest Character boundary if the offset lands mid-scalar.
    static func characterOffset(in line: String, forByteOffset byteOffset: Int) -> Int {
        let utf8 = line.utf8
        guard byteOffset > 0 else { return 0 }
        guard byteOffset < utf8.count else { return line.count }
        let byteIndex = utf8.index(utf8.startIndex, offsetBy: byteOffset)
        guard let index = String.Index(byteIndex, within: line) else {
            // Mid-scalar: walk back to the enclosing Character boundary.
            var probe = byteOffset - 1
            while probe > 0 {
                let candidate = utf8.index(utf8.startIndex, offsetBy: probe)
                if let index = String.Index(candidate, within: line) {
                    return line.distance(from: line.startIndex, to: index)
                }
                probe -= 1
            }
            return 0
        }
        return line.distance(from: line.startIndex, to: index)
    }
}

extension FileHandle {
    func print(_ string: String, as encoding: String.Encoding = .utf8) throws {
        guard let data = string.data(using: encoding)
        else { return }
        try self.write(contentsOf: data)
    }
}

// MARK: - Read/evaluate loops

public extension LineEditor {
    enum Action { case step, exit }

    init(historyPrefix: String) {
        self = .init(historyFile: Self.homeHistoryFile(prefix: historyPrefix))
    }

    static func homeHistoryFile(prefix: String = "repl") -> String {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.\(prefix)_history"
    }

    func readEvaluateLoop(
        prompt: String,
        edit: Bool? = nil,
        eval: (String) -> LineEditor.Action
    ) {
        if edit ?? !isDumb {
            editEvaluateLoop(prompt: prompt, eval: eval)
        } else {
            readLineEvaluateLoop(prompt: prompt, eval: eval)
        }
    }

    /// Async counterpart to ``readEvaluateLoop(prompt:edit:eval:)``.
    ///
    /// Required for `AsyncParsableCommand` trees, whose `run()` is async.
    ///
    /// - Note: `readLine` blocks the calling thread while waiting on the
    ///   terminal. That is acceptable for a REPL, which has nothing else to do,
    ///   but do not drive this loop from a thread shared with other work.
    /// - Note: Takes the caller's isolation so the loop runs in the caller's
    ///   domain. A REPL driver is typically `@MainActor`, and without this the
    ///   `eval` closure would have to cross an isolation boundary on every line.
    func readEvaluateLoop(
        prompt: String,
        edit: Bool? = nil,
        isolation: isolated (any Actor)? = #isolation,
        eval: (String) async -> LineEditor.Action
    ) async {
        let interactive = edit ?? !isDumb
        if interactive {
            beginSession()
        } else {
            Swift.print(prompt, terminator: "")
        }

        while let line = readLine(prompt: interactive ? prompt : "")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        {
            if interactive, !line.isEmpty { addHistory(line) }
            let step = await eval(line)
            if step == .exit { break }
            if !interactive { Swift.print(prompt, terminator: "") }
        }
        Swift.print("")
        if interactive { endSession() }
    }

    func readLineEvaluateLoop(prompt: String, eval: (String) -> LineEditor.Action) {

        print(prompt, terminator: "")
        while let line = readLine()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        {
            let step = eval(line)
            if step == .exit { break }
            print(prompt, terminator: "")
        }
        print("")
    }

    func editEvaluateLoop(prompt: String, eval: (String) -> Action) {
        beginSession()

        while let line = readLine(prompt: prompt)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        {
            if !line.isEmpty { addHistory(line) }
            let step = eval(line)
            if step == .exit { break }
        }
        print("")
        endSession()
    }

    /// Loads persisted history, if a history file is configured.
    func beginSession() {
        guard let historyFile else { return }
        try? loadHistory(at: historyFile)
    }

    /// Writes history back to disk, warning on failure rather than throwing.
    func endSession() {
        guard let historyFile else { return }
        do {
            try saveHistory(to: historyFile)
        } catch {
            fputs("Warning: \(error)\n", stderr)
        }
    }
}
