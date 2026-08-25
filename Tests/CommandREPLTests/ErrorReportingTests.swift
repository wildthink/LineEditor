import ArgumentParser
import Testing
@testable import CommandREPL

@Suite("Error reporting")
struct ErrorReportingTests {

    /// Runs `argv` against the fixture tree the way the REPL does, and returns what escapes.
    ///
    /// A help request only surfaces once the parsed command runs, so this has to go through
    /// `evaluate(argv:)` rather than stopping at `parseAsRoot`.
    private func error(from argv: [String]) throws -> Error {
        do {
            try Root.evaluate(argv: argv)
            Issue.record("expected \(argv) to fail")
            throw ExitCode.failure
        } catch {
            return error
        }
    }

    @Test("names the offending value and lists the accepted ones")
    func reportsTheErrorText() throws {
        let report = try #require(Root.reportMessage(for: error(from: ["build", "x", "--flavor", "banana"])))
        #expect(report.text.contains("banana"))
        for flavor in Flavor.allCases {
            #expect(report.text.contains(flavor.rawValue))
        }
    }

    /// The regression this replaced: a help screen alone renders the command's options but
    /// says nothing about what was typed wrong.
    @Test("the help screen alone drops what fullMessage keeps")
    func helpScreenDropsTheError() throws {
        let error = try error(from: ["build", "x", "--flavor", "banana"])
        #expect(!Root.helpMessage(for: error).contains("banana"))
    }

    @Test("a parse failure is a failure")
    func failureIsRoutedToStandardError() throws {
        let report = try #require(Root.reportMessage(for: error(from: ["build"])))
        #expect(report.isFailure)
    }

    @Test("a help request is not")
    func cleanExitIsRoutedToStandardOutput() throws {
        let report = try #require(Root.reportMessage(for: error(from: ["build", "--help"])))
        #expect(!report.isFailure)
        #expect(report.text.contains("Build a thing."))
    }

    @Test("a bare ExitCode prints nothing, the command having already spoken")
    func bareExitCodeIsSilent() {
        #expect(Root.reportMessage(for: ExitCode.failure) == nil)
        #expect(Root.reportMessage(for: ExitCode.success) == nil)
    }
}
