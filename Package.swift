// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeSessionSync",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeSessionSync",
            path: "Sources",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate",
                              "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist",
                              "-Xlinker", "Sources/Info.plist"])
            ]
        )
    ]
)
