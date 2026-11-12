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
        // Pembaca waktu dari teks ("besok jam 10", "2 jam lagi"); terpisah supaya bisa diuji.
        .target(name: "NotchTime", path: "Sources/NotchTime"),
        .testTarget(name: "NotchTimeTests", dependencies: ["NotchTime"], path: "Tests/NotchTimeTests"),
        // Ringkasan Cognify (cognify-hub.json) dan perintah inbox/; terpisah supaya bisa diuji.
        .target(name: "NotchHub", path: "Sources/NotchHub"),
        .testTarget(name: "NotchHubTests", dependencies: ["NotchHub"], path: "Tests/NotchHubTests"),
        .executableTarget(
            name: "cognify-notch",
            dependencies: ["NotchTime", "NotchHub"],
            path: "Sources/CognifyNotch",
            resources: [.process("Shaders")],
            linkerSettings: [
                // Info.plist di dalam program: teks izin kamera & kalender (lihat notch/Info.plist).
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                              "-Xlinker", Context.packageDirectory + "/Info.plist"]),
            ]
        ),
        .target(name: "CognifyMedia", path: "Sources/CognifyMedia"),
    ]
)
