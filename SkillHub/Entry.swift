import SwiftUI

/// Entry point: `SkillHub` launches the GUI; `SkillHub <command>` runs headless.
/// Product display name is "Skill Library" (`Brand.displayName`); binary stays SkillHub.
/// CLI mode makes adopt/verify/drift scriptable and usable on machines where
/// the GUI isn't set up yet (e.g. a fresh clone on a second device).
@main
enum Entry {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        // Finder/Xcode pass flags like -NSDocumentRevisions...; only treat known
        // subcommands as CLI mode.
        if let command = args.first, CLI.commands.contains(command) {
            exit(CLI.run(command: command, args: Array(args.dropFirst())))
        }
        SkillHubApp.main()
    }
}
