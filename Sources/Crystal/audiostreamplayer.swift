import AudioToolbox
import Cast
import Foundation
import IDisposable
import Scope
import Streams

public class AudioStreamPlayer : IDisposable
{
	public var stream: SynchronizedDataStream

	var subscription: Scope
	var player: AQPlayer

	public init()
	{
		self.stream = SynchronizedDataStream()
		let player = AQPlayer()
		let parse = try! AFSUtility.CreateCustomAudioStreamParser(
			onStreamReady: { (_, asbd, cookieData) in
				try! player.initialize(asbd: asbd, cookieData: cookieData)
			},
			onPackets: player.playPackets!)
		self.subscription = self.stream.addSubscriber() { (data: Data) -> Void in
			try! parse(data)
		}
		self.player = player
	}

	public func dispose() {
		self.subscription.dispose()
		self.player.dispose()
	}
}

public class V2AudioStreamPlayer : IDisposable
{
	public var stream: WriteableStream<AudioData>

	var subscription: Scope
	var player: AQPlayer

	public init()
	{
		var isInitialized = false
		let s = Streams.Stream<AudioData>()
		let player = AQPlayer()
		self.subscription = s.subscribe { (data: AudioData) -> Void in
			if (!isInitialized) {
				let p = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
				p.initialize(to: data.description)
				try! player.initialize(asbd: p, cookieData: nil)
				isInitialized = true
			}
			data.data.withUnsafeBytes() {
				player.playPackets!(UInt32(data.data.count), data.packetInfo?.count ?? 0, $0.baseAddress!, data.packetInfo?.descriptions, AsPointer(data.startTime))
			}
		}
		self.stream = WriteableStream(s)
		self.player = player
	}

	public func dispose() {
		self.subscription.dispose()
		self.player.dispose()
	}
}

public func AsPointer<T>(_ obj: T?) -> UnsafePointer<T>?
{
	if (obj == nil) {
		return nil
	}

	let p = UnsafeMutablePointer<T>.allocate(capacity: 1)
	p.initialize(to: obj!)
	return Cast(p)
}
