// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NagaController",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NagaController", targets: ["NagaController"])
    ],
    targets: [
        .executableTarget(
            name: "NagaController",
            path: "Sources/NagaController",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "NagaControllerTests",
            dependencies: ["NagaController"],
            path: "Tests/NagaControllerTests"
        )
    ]
)
