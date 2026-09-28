// swift-tools-version:5.10
// Notch Cognify (macOS): program kecil yang dijalankan Tauri (src-tauri/src/notch.rs).
// Build: `npm run notch:build` → notch/.build/release/cognify-notch + libcognify-media.dylib.
import PackageDescription

let package = Package(
    name: "CognifyNotch",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "cognify-notch", targets: ["cognify-notch"]),
        // Dimuat ke /usr/bin/perl untuk membaca "yang sedang diputar" (lihat CognifyMedia.m).
        .library(name: "cognify-media", type: .dynamic, targets: ["CognifyMedia"]),
    ],
    targets: [
        .executableTarget(
            name: "cognify-notch",
            path: "Sources/CognifyNotch",
            linkerSettings: [
                // Info.plist di dalam program: teks izin kamera & kalender (lihat notch/Info.plist).
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                              "-Xlinker", Context.packageDirectory + "/Info.plist"]),
            ]
        ),
        .target(name: "CognifyMedia", path: "Sources/CognifyMedia"),
    ]
)
