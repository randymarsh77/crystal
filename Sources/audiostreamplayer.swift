import AudioToolbox
import Cast
import Foundation
import Scope
import Streams

public class AudioStreamPlayer
{
	public var stream: SynchronizedDataStream

	var subscription: Scope

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
	}
}

public class V2AudioStreamPlayer
{
	public var stream: WriteableStream<AudioData>

	public init()
	{
		var isInitialized = false
		let s = Streams.Stream<AudioData>()
		let player = AQPlayer()
		_ = s.subscribe { (data: AudioData) -> Void in
			if (!isInitialized) {
				let p = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
				p.initialize(to: data.description)
				try! player.initialize(asbd: p, cookieData: nil)
				isInitialized = true
			}
			data.data.withUnsafeBytes() { (bytes: UnsafePointer<UInt8>) in
				player.playPackets!(UInt32(data.data.count), data.packetInfo?.count ?? 0, bytes, data.packetInfo?.descriptions, AsPointer(data.startTime))
			}
		}
		stream = WriteableStream(s)
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
