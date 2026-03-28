// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "NTFSWriter",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "NTFSWriter",
            path: "Sources/NTFSWriter",
            publicHeadersPath: "Bridges",
            cSettings: [
                .headerSearchPath("Bridges")
            ],
            linkerSettings: [
                .linkedFramework("DiskArbitration"),
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation")
            ]
        )
    ]
)
