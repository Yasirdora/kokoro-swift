// swift-tools-version:6.0
import Foundation
import PackageDescription

// Locate the vendored sherpa-onnx prebuilt runtime relative to this manifest
// so the package builds without any global installation.
let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .path(percentEncoded: false)
let vendorDir = "\(packageDir)/vendor/sherpa-onnx-v1.12.23-osx-universal2-shared"
let vendorLib = "\(vendorDir)/lib"

// Linker flags must live on the consumer targets (systemLibrary targets do
// not accept linkerSettings). These are "unsafe" only in the SwiftPM sense —
// they pin the prebuilt dylibs via -L and set the runtime rpath so the
// executables find the vendored libraries without installation.
let sherpaLinkSettings: [LinkerSetting] = [
    .unsafeFlags([
        "-L", vendorLib,
        "-Xlinker", "-rpath", "-Xlinker", vendorLib,
    ]),
]

let package = Package(
    name: "KokoroTTS",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "KokoroTTS", targets: ["KokoroTTS"]),
        .executable(name: "kokorocli", targets: ["kokorocli"]),
        .executable(name: "kokoroane", targets: ["kokoroane"]),
        .executable(name: "KokoroDemo", targets: ["KokoroDemo"]),
        .executable(name: "KokoroApp", targets: ["KokoroApp"]),
    ],
    dependencies: [
        .package(name: "mweinbach-kokoro", path: "Packages/mweinbach-kokoro"),
    ],
    targets: [
        .systemLibrary(
            name: "CSherpaOnnx",
            path: "Sources/CSherpaOnnx",
            pkgConfig: "sherpa-onnx",
            providers: [
                .brew(["sherpa-onnx"]),
            ]
        ),
        .target(
            name: "KokoroTTS",
            dependencies: ["CSherpaOnnx"],
            linkerSettings: sherpaLinkSettings
        ),
        .executableTarget(
            name: "kokorocli",
            dependencies: ["KokoroTTS"],
            linkerSettings: sherpaLinkSettings
        ),
        .executableTarget(
            name: "kokoroane",
            dependencies: [
                .product(name: "Kokoro", package: "mweinbach-kokoro"),
            ]
        ),
        .executableTarget(
            name: "KokoroDemo",
            dependencies: ["KokoroTTS"],
            linkerSettings: sherpaLinkSettings
        ),
        .executableTarget(
            name: "KokoroApp",
            dependencies: ["KokoroTTS"],
            linkerSettings: sherpaLinkSettings
        ),
    ]
)
