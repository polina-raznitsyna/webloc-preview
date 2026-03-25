import ArgumentParser

@main
struct WeblocPreview: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "webloc-preview",
        abstract: "Beautiful previews and smart renaming for .webloc files",
        subcommands: [ProcessCommand.self],
        defaultSubcommand: nil
    )
}

struct ProcessCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "process",
        abstract: "Process a .webloc file or folder"
    )

    @Argument(help: "Path to .webloc file or folder")
    var path: String

    func run() throws {
        print("Processing: \(path)")
    }
}
