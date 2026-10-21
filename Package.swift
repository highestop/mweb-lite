// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MWebLite",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MWebLite", targets: ["MWebLite"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "MWebCore", dependencies: ["CSQLite"], resources: [.process("Resources")]),
        .executableTarget(name: "MWebLite", dependencies: ["MWebCore"], resources: [.process("Resources")]),
        .target(name: "CaseReporting", path: "Tests/CaseReporting"),
        .testTarget(name: "MWebCoreTests", dependencies: ["MWebCore", "CSQLite", "CaseReporting"]),
        .testTarget(name: "MWebLiteTests", dependencies: ["MWebLite", "CaseReporting"])
    ]
)
