// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        productTypes: [
            "Vapor": .framework
        ]
    )
#endif

let package = Package(
    name: "CCGateWay",
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0")
    ]
)
