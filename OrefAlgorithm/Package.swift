// swift-tools-version:5.9
import PackageDescription

// The OpenAPS oref algorithm as Trio runs it, for Loop to offer as a second dosing algorithm.
//
// Sources/OrefAlgorithm/Trio is a verbatim copy of Trio's Swift oref and the models it needs
// (see README.md for the Trio commit and copy-from-trio.sh to refresh it). Loop talks to it only
// through Oref.swift, which is the one file written here.

let package = Package(
    name: "OrefAlgorithm",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .watchOS(.v8), .macOS(.v13)],
    products: [
        .library(name: "OrefAlgorithm", targets: ["Trio"]),
        // Command-line runner that prints what each stage computed, for checking a port against Trio's oref.
        .executable(name: "oref-reference", targets: ["oref-reference"])
    ],
    targets: [
        // Named Trio because the copied files qualify their own types as `Trio.` (they are Trio's module there).
        .target(
            name: "Trio",
            path: "Sources/OrefAlgorithm",
            // Trio's package-only logging shim stands in for the Trio app's logger.
            swiftSettings: [.define("TRIO_ALGORITHM_PACKAGE")]
        ),
        .executableTarget(
            name: "oref-reference",
            dependencies: ["Trio"],
            path: "Sources/OrefReference"
        ),
        .testTarget(
            name: "OrefTests",
            dependencies: ["Trio"],
            path: "Tests/OrefTests"
        )
    ]
)
