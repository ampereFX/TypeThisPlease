// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TypeThisPlease",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TypeThisPlease", targets: ["TypeThisPlease"])
    ],
    targets: [
        .executableTarget(
            name: "TypeThisPlease",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreAudio")
            ]
        ),
        .testTarget(
            name: "TypeThisPleaseTests",
            dependencies: ["TypeThisPlease"]
        )
    ]
)
