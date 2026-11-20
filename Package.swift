// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LidStay",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LidStay", targets: ["LidStay"])
    ],
    targets: [
        .executableTarget(
            name: "LidStay",
            path: "Sources/LidStay",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
