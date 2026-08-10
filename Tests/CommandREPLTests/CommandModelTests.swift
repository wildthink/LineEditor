import ArgumentParser
import Testing
@testable import CommandREPL

@Suite("CommandModel")
struct CommandModelTests {

    @Test("introspects a command tree via _dumpHelp")
    func buildsFromDumpHelp() throws {
        let model = try CommandModel.fixture()
        #expect(model.root.commandName == "root")
        // `help` is appended by ArgumentParser's own dump-help generator.
        #expect(model.root.visibleSubcommands.map(\.commandName).sorted()
            == ["build", "help", "nested"])
    }

    @Test("resolves a nested subcommand path")
    func resolvesNestedPath() throws {
        let model = try CommandModel.fixture()
        let (command, consumed) = model.resolve(path: ["nested", "leaf"])
        #expect(command.commandName == "leaf")
        #expect(consumed == ["nested", "leaf"])
    }

    @Test("resolves an alias")
    func resolvesAlias() throws {
        let model = try CommandModel.fixture()
        let (command, consumed) = model.resolve(path: ["b"])
        #expect(command.commandName == "build")
        #expect(consumed == ["b"])
    }

    @Test("stops at the first unrecognized element")
    func stopsAtUnknown() throws {
        let model = try CommandModel.fixture()
        let (command, consumed) = model.resolve(path: ["build", "sometarget"])
        #expect(command.commandName == "build")
        #expect(consumed == ["build"])
    }

    @Test("captures argument kinds, defaults, and repetition")
    func argumentMetadata() throws {
        let model = try CommandModel.fixture()
        let build = model.resolve(path: ["build"]).command

        let flavor = try #require(build.argument(matchingToken: "--flavor"))
        #expect(flavor.kind == .option)
        #expect(flavor.allValues == ["vanilla", "chocolate", "strawberry"])
        #expect(flavor.defaultValue == "vanilla")
        #expect(flavor.tokenNames.contains("-f"))

        let tag = try #require(build.argument(matchingToken: "--tag"))
        #expect(tag.isRepeating)

        let verbose = try #require(build.argument(matchingToken: "--verbose"))
        #expect(verbose.kind == .flag)
        #expect(!verbose.takesValue)

        #expect(build.positionals.map(\.valuePlaceholder) == ["target", "extra"])
        #expect(build.positionals[0].isOptional == false)
        #expect(build.positionals[1].isOptional == true)
    }

    @Test("form arguments exclude parser-injected help and version")
    func excludesInjectedFlags() throws {
        let model = try CommandModel.fixture()
        let build = model.resolve(path: ["build"]).command

        #expect(build.visibleArguments.contains { $0.matchesToken("--help") })
        #expect(!build.formArguments.contains { $0.matchesToken("--help") })
        #expect(!build.formArguments.contains { $0.matchesToken("--version") })
        // Real arguments survive the filter.
        #expect(build.formArguments.contains { $0.matchesToken("--verbose") })
    }
}
