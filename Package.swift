// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Aster", platforms: [.macOS(.v14)],
    products: [.executable(name: "Aster", targets: ["Aster"])],
    dependencies: [.package(url: "https://github.com/AzureAD/microsoft-authentication-library-for-objc", exact: "2.5.0"), .package(url: "https://github.com/openid/AppAuth-iOS", exact: "2.0.0")],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "AsterCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "Aster", dependencies: ["AsterCore", .product(name: "MSAL", package: "microsoft-authentication-library-for-objc"), .product(name: "AppAuth", package: "AppAuth-iOS")]),
        .testTarget(name: "AsterCoreTests", dependencies: ["AsterCore"]),
        .testTarget(name: "AsterAppTests", dependencies: ["Aster", "AsterCore"])
    ]
)
