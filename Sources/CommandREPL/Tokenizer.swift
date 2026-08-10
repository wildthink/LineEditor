//
//  Tokenizer.swift
//  CommandREPL
//

import Foundation

/// One argument parsed out of a command line.
public struct Token: Sendable, Equatable {
    /// The token's value with quotes and escapes resolved.
    public var text: String
    /// Character offset of the token's first character in the raw line.
    public var start: Int
    /// Character offset one past the token's last character in the raw line.
    public var end: Int
    /// True when any part of the token was quoted.
    public var isQuoted: Bool

    public init(text: String, start: Int, end: Int, isQuoted: Bool = false) {
        self.text = text
        self.start = start
        self.end = end
        self.isQuoted = isQuoted
    }
}

/// Shell-style tokenizer for REPL input.
///
/// Replaces `line.split(separator: " ")`, which mangles any argument containing
/// a space -- a real problem for a tool whose primary argument is a file path.
///
/// Supported: whitespace separation, `'single'` quoting (fully literal),
/// `"double"` quoting (with `\"` and `\\` escapes), and backslash escapes
/// outside quotes. An unterminated quote runs to end of line rather than
/// failing, because the user is mid-typing whenever completion runs.
public enum Tokenizer {

    /// Tokenizes an entire line.
    public static func tokens(in line: String) -> [Token] {
        let chars = Array(line)
        var tokens: [Token] = []
        var i = 0

        while i < chars.count {
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            guard i < chars.count else { break }

            let start = i
            var text = ""
            var quote: Character?
            var isQuoted = false

            while i < chars.count {
                let c = chars[i]
                if let q = quote {
                    if c == q {
                        quote = nil
                        i += 1
                    } else if q == "\"", c == "\\", i + 1 < chars.count {
                        text.append(chars[i + 1])
                        i += 2
                    } else {
                        text.append(c)
                        i += 1
                    }
                    continue
                }
                if c == "'" || c == "\"" {
                    quote = c
                    isQuoted = true
                    i += 1
                } else if c == "\\", i + 1 < chars.count {
                    text.append(chars[i + 1])
                    i += 2
                } else if c.isWhitespace {
                    break
                } else {
                    text.append(c)
                    i += 1
                }
            }

            tokens.append(Token(text: text, start: start, end: i, isQuoted: isQuoted))
        }

        return tokens
    }

    /// Splits a line at the cursor into finished tokens and the token being typed.
    ///
    /// Tokenizing only the text *before* the cursor naturally truncates the
    /// in-progress token, which is exactly what completion needs. When the
    /// cursor sits in whitespace, `partial` is nil and the caller should treat
    /// the cursor as the start of a brand new token.
    ///
    /// - Returns: `completed` are the tokens fully typed before the one under
    ///   the cursor; `partial` is the token the cursor is inside or at the end
    ///   of, or nil if the cursor follows whitespace.
    public static func split(
        _ line: String,
        cursor: Int
    ) -> (completed: [Token], partial: Token?) {
        let chars = Array(line)
        let cut = max(0, min(cursor, chars.count))
        let head = String(chars[0..<cut])
        var tokens = tokens(in: head)

        // The cursor continues the last token only if the character immediately
        // before it is not whitespace. `foo |` starts a new token; `foo|` does not.
        let touchesLastToken = cut > 0 && !chars[cut - 1].isWhitespace
        guard touchesLastToken, !tokens.isEmpty else {
            return (tokens, nil)
        }
        let partial = tokens.removeLast()
        return (tokens, partial)
    }

    /// Re-quotes a value for insertion into a command line, if it needs it.
    public static func quoteIfNeeded(_ value: String) -> String {
        let needsQuoting = value.contains(where: { $0.isWhitespace })
            || value.contains("\"") || value.contains("'")
        guard needsQuoting else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
