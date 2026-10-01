import AppKit
import SwiftUI

/// Developer aid that renders a view from the cached snapshot to a PNG and exits,
/// so layout changes can be checked without opening the app:
/// `--render-preview out.png` draws the menu-bar popover and
/// `--render-dashboard out.png` the dashboard window. Add
/// `-dashboardTheme <theme>` (e.g. `orbital`) to pick a theme for this run only.
enum PreviewRenderer {
    @MainActor
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let (flag, output) = request(in: arguments) else { return }
        let capacity = CapacityStore(service: .live)
        let missions = MissionStore()
        let theme = UserDefaults.standard.string(forKey: DashboardTheme.storageKey)
            .flatMap(DashboardTheme.init(rawValue:)) ?? .default

        if flag == "--render-preview" {
            render(
                ThemedMenu(capacity: capacity, missions: missions, staticLayout: true)
                    .frame(width: 430)
                    .fixedSize(horizontal: false, vertical: true),
                to: output
            )
        } else {
            let size = theme.showsMissions ? CGSize(width: 1440, height: 900) : CGSize(width: 520, height: 860)
            render(
                ThemedDashboard(capacity: capacity, missions: missions, staticLayout: true)
                    .frame(width: size.width, height: size.height),
                to: output
            )
        }
    }

    private static func request(in arguments: [String]) -> (String, URL)? {
        for flag in ["--render-preview", "--render-dashboard"] {
            if let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) {
                return (flag, URL(fileURLWithPath: arguments[index + 1]))
            }
        }
        return nil
    }

    @MainActor
    private static func render(_ view: some View, to output: URL) -> Never {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("Preview render failed.\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: output)
            print(output.path)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Could not write preview: \(error)\n".utf8))
            exit(1)
        }
    }
}
