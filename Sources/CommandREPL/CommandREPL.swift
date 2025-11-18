//
//  CommandREPL.swift
//  LineEditor
//
//  Created by Jason Jobe on 11/18/25.
//

#if canImport(ArgumentParser)
import ArgumentParser
import Foundation

public extension ParsableCommand {
        
    static func evaluate(line: String) throws {
        let argv = line.split(separator: " ")
        try evaluate(argv: argv)
    }
    
    static func evaluate(argv: [String.SubSequence]) throws {
        try evaluate(argv: argv.map { String($0) })
    }

    static func evaluate(argv: Array<String.SubSequence>.SubSequence) throws {
        try evaluate(argv: argv.map { String($0) })
    }

    static func evaluate<S: StringProtocol>(argv: [S]) throws {
        try evaluate(argv: argv.map { String($0) })
    }
    
    static func evaluate(argv: [String]) throws {
        var cmd = try Self.parseAsRoot(argv)
        try cmd.run()
    }
    
    static func helpMessage(for error: Error, maxColumns: Int = 80) -> String {
        let m = Mirror(reflecting: error)
        for c in m.children {
            switch c.value {
                case let stack as [ParsableCommand.Type]:
                    if let last = stack.last {
                        var str = ""
                        print(last.helpMessage(columns: maxColumns), to: &str)
                        return str
                    }
                default:
                    break
            }
        }
        return "No help available for \(error.localizedDescription)"
    }
    
    static func report(error: Error) {
        print(helpMessage(for: error))
    }
}
#endif
