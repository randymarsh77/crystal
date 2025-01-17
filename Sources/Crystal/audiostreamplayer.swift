import AudioToolbox
import Cast
import Foundation
import IDisposable
import Scope

public protocol ICanBePipedTo<Element>: Sendable {
	associatedtype Element
	func consume(_ data: Element)
}

@available(iOS 13.0, *)
@available(macOS 10.15, *)
extension AsyncStream {
	func pipe(_ to: any ICanBePipedTo<Self.Element>) async {
		for await next in self {
			to.consume(next)
		}
	}
}

@available(iOS 13.0.0, *)
@available(macOS 10.15.0, *)
public actor V2AudioStreamPlayer: IAsyncDisposable, Sendable {
	public let player: AQPlayer

	var isInitialized = false

	public init(_ behavior: AQPlayerBehavior = .infiniteStream) {
		self.player = AQPlayer(behavior)
	}

	public func dispose() async {
		await self.player.dispose()
	}

	public func consume(_ audio: AudioData) async {
		if !self.isInitialized {
			let p = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
			p.initialize(to: audio.streamDescription)
			try! await player.initialize(asbd: p, cookieData: nil)
			self.isInitialized = true
		}
		await player.play(audio)
	}
}

public func asPointer<T>(_ obj: T?) -> UnsafePointer<T>? {
	if obj == nil {
		return nil
	}

	let p = UnsafeMutablePointer<T>.allocate(capacity: 1)
	p.initialize(to: obj!)
	return cast(p)
}
