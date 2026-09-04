// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Stash",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Stash", targets: ["Stash"])],
    targets: [
        .executableTarget(
            name: "Stash",
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
