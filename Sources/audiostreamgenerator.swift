import AudioToolbox
import Foundation
import Time

public class AudioStreamGenerator
{
	public var stream: SynchronizedDataStreamWithMetadata<Double>

	var running: Bool = false
	var queue: AudioQueueRef? = nil

	public init()
	{
		self.stream = SynchronizedDataStreamWithMetadata<Double>()

		let propertyData = try! ASBDFactory.CreateDefaultDescription(format: kAudioFormatMPEG4AAC)
		let options = ADTSEncodingOptions(dataFormat: .AAC_LC, crc: true)
		let encode = ADTSUtility.CreateADTSEncoder(options: options)
		let queue = try! AQFactory.CreateDefaultInputQueue(propertyData: propertyData) { (data: AQInputData) -> Void in
			let encodedData = encode(data)
			self.stream.publish(chunk: encodedData, meta: Time.ConvertTimeStamp(data.ts!.pointee.mHostTime))
		}

		self.queue = queue
	}

	public func start()
	{
		if running { return }
		running = true
		AudioQueueStart(self.queue!, nil)
	}

	public func stop()
	{
		if !running { return }
		AudioQueueStop(self.queue!, false)
	}
}
