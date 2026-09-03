import AppKit
import UniformTypeIdentifiers

@MainActor
enum ConfigurationFilePanel {
    static func chooseYAML() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Mihomo Configuration"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "yaml")!,
            UTType(filenameExtension: "yml")!,
        ]
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
