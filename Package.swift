// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MWebLite",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MWebLite", targets: ["MWebLite"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "MWebCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "MWebLite", dependencies: ["MWebCore"], resources: [.process("Resources")]),
        .testTarget(name: "MWebCoreTests", dependencies: ["MWebCore", "CSQLite"]),
        .testTarget(name: "MWebLiteTests", dependencies: ["MWebLite"])
    ]
)
