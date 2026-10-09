// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "TwoNest", platforms: [.iOS(.v17)], products: [.library(name: "TwoNest", targets: ["TwoNest"])], targets: [.target(name: "TwoNest")])
