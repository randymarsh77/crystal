// swift-tools-version:6.0
import PackageDescription

let package = Package(
	name: "Crystal",
	products: [
		.library(
			name: "Crystal",
			targets: ["Crystal"]
		)
	],
	dependencies: [
		.package(url: "https://github.com/randymarsh77/cancellation", branch: "master"),
		.package(url: "https://github.com/randymarsh77/cast", branch: "master"),
		.package(url: "https://github.com/randymarsh77/scope", branch: "master"),
		.package(url: "https://github.com/randymarsh77/sockets", branch: "master"),
		.package(url: "https://github.com/randymarsh77/time", branch: "master"),
	],
	targets: [
		.target(
			name: "Crystal",
			dependencies: [
				.product(name: "Cancellation", package: "Cancellation"),
				.product(name: "Cast", package: "Cast"),
				.product(name: "Scope", package: "Scope"),
				.product(name: "Sockets", package: "Sockets"),
				.product(name: "Time", package: "Time"),
			]
		),
		.testTarget(name: "CrystalTests", dependencies: ["Crystal"]),
	]
)
