// swift-tools-version:5.1
import PackageDescription

let package = Package(
	name: "Crystal",
	products: [
		.library(
			name: "Crystal",
			targets: ["Crystal"]
		),
	],
	dependencies: [
		.package(url: "https://github.com/randymarsh77/cancellation", .branch("master")),
		.package(url: "https://github.com/randymarsh77/cast", .branch("master")),
		.package(url: "https://github.com/randymarsh77/scope", .branch("master")),
		.package(url: "https://github.com/randymarsh77/sockets", .branch("master")),
		.package(url: "https://github.com/randymarsh77/streams", .branch("master")),
		.package(url: "https://github.com/randymarsh77/time", .branch("master")),
	],
	targets: [
		.target(
			name: "Crystal",
			dependencies: [
				"Cancellation",
				"Cast",
				"Scope",
				"Sockets",
				"Streams",
				"Time",
			]
		),
	]
)
