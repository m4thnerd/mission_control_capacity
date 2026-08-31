// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "mission-control-capacity",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CapacityCore", targets: ["CapacityCore"]),
        .executable(name: "MissionControlCapacity", targets: ["MissionControlCapacity"]),
        .executable(name: "capacityctl", targets: ["capacityctl"])
    ],
    targets: [
        .target(name: "CapacityCore"),
        .executableTarget(
            name: "MissionControlCapacity",
            dependencies: ["CapacityCore"]
        ),
        .executableTarget(
            name: "capacityctl",
            dependencies: ["CapacityCore"]
        )
    ]
)
