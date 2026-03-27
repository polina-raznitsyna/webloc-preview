import ArgumentParser

@main
struct WeblocPreview: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "webloc-preview",
        abstract: "Beautiful previews and smart renaming for .webloc files",
        subcommands: [
            ProcessCommand.self,
            WatchCommand.self,
            StopCommand.self,
            StatusCommand.self,
            CleanupCommand.self,
            SetupTelegramCommand.self,
        ]
    )
}
