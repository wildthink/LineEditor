import ArgumentParser
import Testing
@testable import CommandREPL

@Suite("CommandForm")
@MainActor
struct CommandFormTests {

    private func form(model: CommandModel, path: [String] = ["build"]) -> CommandForm<Root> {
        CommandForm(
            root: Root.self,
            model: model,
            path: path,
            command: model.resolve(path: path).command)
    }

    @Test("assembles an argv from answered fields")
    func assemblesArgv() throws {
        let model = try CommandModel.fixture()
        // target, extra, flavor, tag(x1 then blank), config, output-dir, pick, verbose
        let input = ScriptedInput(["mytarget", "", "chocolate", "tags", "", "", "", "", "y"])

        let argv = try #require(form(model: model).run(editor: input))
        #expect(argv == ["build", "--flavor", "chocolate", "--tag", "tags", "--verbose", "mytarget"])
    }

    @Test("the assembled argv actually parses")
    func argvParses() throws {
        let model = try CommandModel.fixture()
        let input = ScriptedInput(["mytarget", "", "chocolate", "", "", "", "", "n"])

        let argv = try #require(form(model: model).run(editor: input))
        let command = try #require(try Root.parseAsRoot(argv) as? Build)
        #expect(command.target == "mytarget")
        #expect(command.flavor == .chocolate)
        #expect(command.verbose == false)
    }

    @Test("blank answers omit optional arguments entirely")
    func blankOmitsOptionals() throws {
        let model = try CommandModel.fixture()
        let input = ScriptedInput(["mytarget", "", "", "", "", "", "", ""])

        let argv = try #require(form(model: model).run(editor: input))
        // Only the required positional survives; ArgumentParser applies its own
        // defaults rather than the form re-injecting them.
        #expect(argv == ["build", "mytarget"])
    }

    @Test("an enum field accepts a choice number")
    func enumByNumber() throws {
        let model = try CommandModel.fixture()
        // "2" selects the second choice, chocolate.
        let input = ScriptedInput(["mytarget", "", "2", "", "", "", "", ""])

        let argv = try #require(form(model: model).run(editor: input))
        #expect(argv.contains("chocolate"))
    }

    @Test("a repeating option collects until a blank line")
    func repeatingOption() throws {
        let model = try CommandModel.fixture()
        let input = ScriptedInput(["mytarget", "", "", "one", "two", "three", "", "", "", "", ""])

        let argv = try #require(form(model: model).run(editor: input))
        #expect(argv == ["build", "--tag", "one", "--tag", "two", "--tag", "three", "mytarget"])
    }

    @Test("a required field re-prompts on a blank answer")
    func requiredFieldRepeats() throws {
        let model = try CommandModel.fixture()
        let input = ScriptedInput(["", "mytarget", "", "", "", "", "", "", ""])

        let argv = try #require(form(model: model).run(editor: input))
        #expect(argv.contains("mytarget"))
        // Two prompts were issued for <target>: the blank, then the real answer.
        #expect(input.prompts.filter { $0.contains("<target>") }.count == 2)
    }

    @Test("never prompts for --help or --version")
    func skipsInjectedFlags() throws {
        let model = try CommandModel.fixture()
        let input = ScriptedInput(["mytarget", "", "", "", "", "", "", ""])
        _ = form(model: model).run(editor: input)

        #expect(!input.prompts.contains { $0.contains("--help") })
        #expect(!input.prompts.contains { $0.contains("--version") })
    }

    @Test("EOF cancels the form")
    func eofCancels() throws {
        let model = try CommandModel.fixture()
        let input = ScriptedInput([])  // immediate EOF
        #expect(form(model: model).run(editor: input) == nil)
    }

    @Test("a positional that looks like an option gets a terminator")
    func terminatorForDashedPositional() throws {
        let model = try CommandModel.fixture()
        let input = ScriptedInput(["-weird", "", "", "", "", "", "", ""])

        let argv = try #require(form(model: model).run(editor: input))
        #expect(argv == ["build", "--", "-weird"])
    }
}
