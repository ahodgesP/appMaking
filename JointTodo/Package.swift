// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JointTodo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "JointTodo", targets: ["JointTodo"]),
        .executable(name: "jointodo", targets: ["JointTodoCLI"]),
    ],
    targets: [
        .target(name: "JointTodoCore"),
        .executableTarget(
            name: "JointTodo",
            dependencies: ["JointTodoCore"]
        ),
        .executableTarget(
            name: "JointTodoCLI",
            dependencies: ["JointTodoCore"]
        ),
        .testTarget(
            name: "JointTodoCoreTests",
            dependencies: ["JointTodoCore"]
        ),
    ]
)
