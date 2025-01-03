import AudioToolbox
import Cancellation
import Foundation
import Scope
import Sockets

@available(iOS 13.0, *)
@available(macOS 10.15, *)
extension Socket {
	public func createAudioStream() -> AsyncStream<AudioData> {
		return AsyncStream<AudioData> { continuation in
			let tokenSource = CancellationTokenSource()
			continuation.onTermination = { _ in
				tokenSource.cancel()
			}

			var description: AudioStreamBasicDescription?

			let parse = try! AFSUtility.createCustomAudioStreamParser(
				onStreamReady: { (_, asbd, _) in
					description = asbd.pointee
				},
				onPackets: {
					(
						_ numBytes: UInt32, _ numPackets: UInt32, _ inputData: UnsafeRawPointer,
						_ packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?,
						_ startTime: UnsafePointer<AudioTimeStamp>?
					) in
					continuation.yield(
						AudioData.create(
							description!, numBytes, numPackets, inputData, packetDescriptions,
							startTime))
				})

			Task {
				while !tokenSource.isCancellationRequested && self.isValid,
					let data = await self.read(maxBytes: 4 * 1024)
				{
					try! parse(data)
				}
			}
		}
	}
}
