// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UpKeepy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "UpKeepy",
            path: "Sources/UpKeepy",
            // On reste en mode langage Swift 5 : la concurrence stricte de Swift 6
            // n'apporte rien ici et complique inutilement une app GUI simple.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
