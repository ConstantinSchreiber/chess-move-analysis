// swift-tools-version:5.10
import PackageDescription

// ARMv8.2 dot-product instructions (SDOT/UDOT) speed up NNUE inference, but Apple added them with
// the A13. iOS 17 still runs on A12 devices (iPhone XS/XR), where they would SIGILL, so they stay
// off until the deployment target drops A12 (iOS 26+).
let useDotProd = false

var stockfishDefines: [CXXSetting] = [
    .define("STOCKFISHKIT"),  // see Sources/CStockfish/PATCHES.md
    .define("NDEBUG"),
    .define("IS_64BIT"),
    .define("NNUE_EMBEDDING_OFF"),
    .headerSearchPath("src"),
    // -O3 even in Debug: an unoptimized engine is ~20x slower. The last -O flag wins.
    .unsafeFlags(["-O3", "-funroll-loops", "-fno-math-errno",
                  "-Wno-unused-command-line-argument", "-Wno-shorten-64-to-32"]),
    // NEON/popcount only on arm64 (devices, Apple-silicon simulators, Macs); an Intel-Mac
    // simulator (x86_64) compiles Stockfish's generic 64-bit code instead.
    .unsafeFlags(["-Xarch_arm64", "-DUSE_NEON=8", "-Xarch_arm64", "-DUSE_POPCNT"]),
    // iOS 17 requires an A12 or newer, so the A12 feature set (ARMv8.3) is always available.
    .unsafeFlags(["-Xarch_arm64", "-mcpu=apple-a12"], .when(platforms: [.iOS])),
]
if useDotProd {
    stockfishDefines += [
        .unsafeFlags(["-Xarch_arm64", "-DUSE_NEON_DOTPROD", "-Xarch_arm64", "-march=armv8.2-a+dotprod"]),
    ]
}

let package = Package(
    name: "StockfishKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StockfishKit", targets: ["StockfishKit"]),
    ],
    targets: [
        .target(
            name: "CStockfish",
            path: "Sources/CStockfish",
            exclude: ["Copying.txt", "AUTHORS", "PATCHES.md", "STOCKFISH_VERSION", "src/incbin/UNLICENCE"],
            sources: ["src", "bridge"],
            publicHeadersPath: "include",
            cxxSettings: stockfishDefines,
            linkerSettings: [.linkedLibrary("c++")]
        ),
        .target(
            name: "StockfishKit",
            dependencies: ["CStockfish"],
            path: "Sources/StockfishKit"
        ),
        .testTarget(
            name: "StockfishKitTests",
            dependencies: ["StockfishKit"],
            path: "Tests/StockfishKitTests"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
