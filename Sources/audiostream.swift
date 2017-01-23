import AudioToolbox
import Foundation
import Sockets
import Streams

public extension Socket
{
	public func createAudioStream() -> ReadableStream<AudioData>
	{
		let stream = Streams.Stream<AudioData>()
		var description: AudioStreamBasicDescription? = nil

		let parse = try! AFSUtility.CreateCustomAudioStreamParser(
			onStreamReady: { (_, asbd, cookieData) in
				description = asbd.pointee
		},
			onPackets: { (_ numBytes: UInt32, _ numPackets: UInt32, _ inputData: UnsafeRawPointer, _ packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?, _ startTime: UnsafePointer<AudioTimeStamp>?) in
				stream.publish(AudioData.Create(description!, numBytes, numPackets, inputData, packetDescriptions, startTime))
		})

		DispatchQueue.global().async {
			while let data = self.read(maxBytes: 4 * 1024) {
				try! parse(data)
			}
		}

		return ReadableStream(stream)
	}
}
