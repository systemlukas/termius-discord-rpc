// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TermiusRPC",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TermiusRPC",
            path: "TermiusRPC/TermiusRPC",
            exclude: ["Info.plist", "TermiusRPC.entitlements", "Assets.xcassets"]
        ),
        .testTarget(
            name: "TermiusRPCTests",
            dependencies: ["TermiusRPC"],
            path: "TermiusRPC/TermiusRPCTests"
        )
    ]
)
