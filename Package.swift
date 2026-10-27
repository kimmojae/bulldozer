// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bulldozer",
    platforms: [.macOS("27.0")],
    targets: [
        // macOS 27 비공개 API(MenuBarClientCore)를 감싸는 Objective-C 타깃
        .target(name: "MenuBarClientShim"),
        .executableTarget(name: "Bulldozer", dependencies: ["MenuBarClientShim"]),
        .testTarget(name: "BulldozerTests", dependencies: ["Bulldozer"])
    ]
)
