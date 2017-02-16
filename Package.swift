import PackageDescription

let package = Package(
    name: "Crystal",
    dependencies: [
		.Package(url: "https://github.com/randymarsh77/cancellation", majorVersion: 1),
		.Package(url: "https://github.com/randymarsh77/cast", majorVersion: 1),
		.Package(url: "https://github.com/randymarsh77/scope", majorVersion: 1),
		.Package(url: "https://github.com/randymarsh77/sockets", majorVersion: 1),
		.Package(url: "https://github.com/randymarsh77/streams", majorVersion: 0),
		.Package(url: "https://github.com/randymarsh77/time", majorVersion: 2),
	]
)
