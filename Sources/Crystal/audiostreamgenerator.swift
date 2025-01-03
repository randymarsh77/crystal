import AudioToolbox
import Foundation
import Time

public struct SynchronizedAudioChunk: Sendable {
	public let chunk: Data
	public let time: Time
}

@available(iOS 13.0, *)
@available(macOS 10.15, *)
public func createSynchronizedAuioStreamFromDefaultInput() -> AsyncStream<SynchronizedAudioChunk> {
	return AsyncStream { continuation in
		let propertyData = try! ASBDFactory.createDefaultDescription(format: kAudioFormatMPEG4AAC)
		let options = ADTSEncodingOptions(dataFormat: .aacLC, crc: true)
		let encode = ADTSUtility.createADTSEncoder(options: options)
		let queue = try! AQFactory.createDefaultInputQueue(propertyData: propertyData) {
			(data: AQInputData) -> Void in
			let encodedData = encode(data)
			let chunk = SynchronizedAudioChunk(
				chunk: encodedData, time: Time.fromSystemTimeStamp(data.ts!.pointee.mHostTime))
			continuation.yield(chunk)
		}

		actor QueueWrapper {
			let queue: AudioQueueRef
			init(_ queue: AudioQueueRef) {
				self.queue = queue
			}

			public func start() {
				AudioQueueStart(queue, nil)
			}

			public func stop() {
				AudioQueueStop(queue, false)
			}
		}

		let queueWrapper = QueueWrapper(queue)

		continuation.onTermination = { @Sendable _ in
			Task {
				await queueWrapper.stop()
			}
		}

		Task {
			await queueWrapper.start()
		}
	}
}
