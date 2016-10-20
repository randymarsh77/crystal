import AudioToolbox
import Foundation
import Scope

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
