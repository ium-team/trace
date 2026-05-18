import Foundation

@MainActor
final class CmuxDeliveryAdapter: DeliveryAdapter {
    private let bundleIdentifier = "com.cmuxterm.app"

    func supports(_ destination: AppDestination) -> Bool {
        destination.bundleIdentifier == bundleIdentifier
    }

    func destinations(for destination: AppDestination) -> [AppSpecificDestination] {
        guard let tree = loadTree() else { return [] }

        return tree.windows.flatMap { window in
            window.workspaces.flatMap { workspace in
                workspace.panes.flatMap { pane in
                    pane.surfaces.map { surface in
                        makeDestination(
                            window: window,
                            workspace: workspace,
                            pane: pane,
                            surface: surface
                        )
                    }
                }
            }
        }
    }

    private func makeDestination(
        window: CmuxTree.Window,
        workspace: CmuxTree.Workspace,
        pane: CmuxTree.Pane,
        surface: CmuxTree.Surface
    ) -> AppSpecificDestination {
        let surfaceTitle = surface.title.isEmpty ? surface.ref : surface.title
        let title = "\(workspace.title) · \(surfaceTitle)"
        let detail = [
            window.ref,
            workspace.ref,
            pane.ref,
            surface.ref,
            surface.type
        ].joined(separator: " / ")

        return AppSpecificDestination(
            title: title,
            detail: detail,
            focus: { [weak self] in
                guard let self else {
                    throw TraceError.deliveryFailed("cmux 전달 어댑터를 사용할 수 없습니다.")
                }
                try self.focus(surface: surface.ref)
            }
        )
    }

    private func loadTree() -> CmuxTree? {
        guard let data = try? runCmux(arguments: ["tree", "--all", "--json"]) else {
            return nil
        }
        return try? JSONDecoder().decode(CmuxTree.self, from: data)
    }

    private func focus(surface: String) throws {
        _ = try runCmux(arguments: [
            "rpc",
            "surface.focus",
            "{\"surface_id\":\"\(surface)\"}",
            "--json"
        ])
    }

    private func runCmux(arguments: [String]) throws -> Data {
        guard let executableURL = cmuxExecutableURL else {
            throw TraceError.deliveryFailed("cmux CLI를 찾지 못했습니다.")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw TraceError.deliveryFailed(message?.isEmpty == false ? message! : "cmux 명령 실행에 실패했습니다.")
        }

        return outputData
    }

    private var cmuxExecutableURL: URL? {
        let candidates = [
            URL(fileURLWithPath: "/Applications/cmux.app/Contents/Resources/bin/cmux"),
            URL(fileURLWithPath: "/usr/local/bin/cmux"),
            URL(fileURLWithPath: "/opt/homebrew/bin/cmux")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private struct CmuxTree: Decodable {
    var windows: [Window]

    struct Window: Decodable {
        var ref: String
        var workspaces: [Workspace]
    }

    struct Workspace: Decodable {
        var ref: String
        var title: String
        var panes: [Pane]
    }

    struct Pane: Decodable {
        var ref: String
        var surfaces: [Surface]
    }

    struct Surface: Decodable {
        var ref: String
        var title: String
        var type: String
    }
}
