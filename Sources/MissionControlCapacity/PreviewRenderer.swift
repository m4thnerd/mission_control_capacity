import AppKit
import SwiftUI

/// Developer aid: `MissionControlCapacity --render-preview out.png` renders the
/// menu-bar dashboard from the cached snapshot to a PNG and exits, so layout
/// changes can be checked without clicking the menu bar item.
enum PreviewRenderer {
    @MainActor
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-preview"),
              arguments.indices.contains(flag + 1) else { return }
        let output = URL(fileURLWithPath: arguments[flag + 1])

        let store = CapacityStore(service: .live)
        let view = DashboardView(store: store, compact: true, staticLayout: true)
            .frame(width: 430)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(nsColor: .windowBackgroundColor))
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
