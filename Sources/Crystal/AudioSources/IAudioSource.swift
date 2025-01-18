import Foundation
import IDisposable
import Scope

@available(iOS 13.0.0, *)
@available(macOS 10.15, *)
public protocol IAudioSource {
	func start() async -> (Scope, AsyncStream<AudioData>)
}
