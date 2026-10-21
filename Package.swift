// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
  name: "DasungControl",
  platforms: [.macOS(.v15)],
  products: [.executable(name: "DasungControl", targets: ["DasungControl"])],
  targets: [
    .target(name: "DasungKit", swiftSettings: strict),
    .executableTarget(
      name: "DasungControl",
      dependencies: ["DasungKit"],
      swiftSettings: strict
    ),
    .testTarget(name: "DasungKitTests", dependencies: ["DasungKit"], swiftSettings: strict),
  ]
)
