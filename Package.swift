// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Trace",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Trace", targets: ["Trace"])
    ],
    targets: [
        .executableTarget(
            name: "Trace",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "TraceTests",
            dependencies: ["Trace"]
        )
    ]
)
