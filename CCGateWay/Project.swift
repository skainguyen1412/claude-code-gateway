import ProjectDescription

let project = Project(
    name: "CCGateWay",
    targets: [
        .target(
            name: "CCGateWay",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.CCGateWay",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "LSUIElement": .boolean(true),
                "NSMainStoryboardFile": .string(""),
                "NSPrincipalClass": .string("NSApplication"),
            ]),
            buildableFolders: [
                "CCGateWay/Sources",
                "CCGateWay/Resources",
            ],
            entitlements: "CCGateWay.entitlements",
            dependencies: [
                .external(name: "Vapor")
            ],
            settings: .settings(
                base: [
                    "CODE_SIGN_STYLE": "Automatic",
                    "CODE_SIGN_IDENTITY": "Apple Development",
                    "DEVELOPMENT_TEAM": "52DR6F4N35",
                    "ENABLE_HARDENED_RUNTIME": "YES",
                ],
                configurations: [],
                defaultSettings: .recommended
            )
        ),
        .target(
            name: "CCGateWayTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.tuist.CCGateWayTests",
            infoPlist: .default,
            buildableFolders: [
                "CCGateWay/Tests"
            ],
            dependencies: [.target(name: "CCGateWay")]
        ),
    ]
)
