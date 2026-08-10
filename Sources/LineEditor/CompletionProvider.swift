//
//  CompletionProvider.swift
//  LineEditor
//

import Foundation

/// A single completion candidate.
///
/// `value` is the text that should replace the *token* under the cursor, not
/// the whole line. `LineEditor` performs the splice into the surrounding line
/// before handing anything to the underlying editor, so providers only ever
/// reason about the token they are completing.
public struct Completion: Sendable, Hashable {
    /// The token text to insert.
    public var value: String
    /// Optional label shown in place of `value` when candidates are listed.
    public var display: String?
    /// Optional trailing description, e.g. an enum case's documentation.
    public var detail: String?

    public init(_ value: String, display: String? = nil, detail: String? = nil) {
        self.value = value
        self.display = display
        self.detail = detail
    }
}

/// The span of `line` that a set of completions should replace.
///
/// Providers return this alongside their candidates so `LineEditor` knows how
/// much of the buffer to overwrite. The range must end at or before the cursor
/// -- bestline repositions the cursor by the length delta of the replaced line,
/// which only yields the right result when edits stay at or behind the cursor.
public struct CompletionRequest: Sendable {
    /// The full contents of the edit buffer.
    public var line: String
    /// Byte-agnostic character offset of the cursor within `line`.
    public var cursor: Int

    public init(line: String, cursor: Int) {
        self.line = line
        self.cursor = cursor
    }

    /// The substring from `start` up to the cursor.
    public func text(from start: Int) -> String {
        let s = line.index(line.startIndex, offsetBy: max(0, min(start, line.count)))
        let c = line.index(line.startIndex, offsetBy: max(0, min(cursor, line.count)))
        return s <= c ? String(line[s..<c]) : ""
    }
}

/// The result of a completion query: what to replace, and what to replace it with.
public struct CompletionResult: Sendable {
    /// Character offset in the line where the replaced token begins. The token
    /// is understood to extend from here to the cursor.
    public var replacingFrom: Int
    /// Candidate replacements.
    public var candidates: [Completion]

    public init(replacingFrom: Int, candidates: [Completion]) {
        self.replacingFrom = replacingFrom
        self.candidates = candidates
    }

    /// A result with no candidates. `replacingFrom` is irrelevant but must be
    /// in range, so it defaults to the start of the line.
    public static let none = CompletionResult(replacingFrom: 0, candidates: [])
}

/// Supplies Tab completions and inline hints for a `LineEditor`.
public protocol CompletionProvider: Sendable {
    /// Candidates for the token under the cursor.
    func complete(_ request: CompletionRequest) -> CompletionResult

    /// Dim text rendered to the right of the cursor. Return `nil` for none.
    ///
    /// bestline only renders hints when the cursor is at end-of-line, and it
    /// passes the buffer without a cursor position, so implementations should
    /// treat the hint as "what comes next after this whole line".
    func hint(for line: String) -> String?
}

public extension CompletionProvider {
    func hint(for line: String) -> String? { nil }
}

/// The historical `setCompletions(_:)` behaviour: match whole-line prefixes
/// against a fixed word list.
///
/// Retained so existing callers keep working after the bestline migration.
/// Prefer a purpose-built ``CompletionProvider`` -- this one has no notion of
/// tokens, so it only ever completes the first word of a line.
public struct PrefixCompletionProvider: CompletionProvider {
    public var words: [String]

    public init(words: [String]) {
        self.words = words
    }

    public func complete(_ request: CompletionRequest) -> CompletionResult {
        let prefix = request.text(from: 0)
        return CompletionResult(
            replacingFrom: 0,
            candidates: words.filter { $0.hasPrefix(prefix) }.map { Completion($0) }
        )
    }
}
