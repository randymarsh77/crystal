import AudioToolbox
import Foundation
import IDisposable
import Time

public class AudioStreamGenerator : IDisposable
{
	public var stream: SynchronizedDataStreamWithMetadata<Double>
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
		AudioQueueStart(self.queue!, nil)

	}

	public func dispose()
	{
		AudioQueueStop(self.queue!, false)
	}
}
